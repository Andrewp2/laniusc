// Match compact arguments to compact parameter rows.
//
// Both families already carry dense start/count/ordinal metadata, so every
// argument lane projects its parameter row directly. No serial list walk or
// pointer-jump scratch is needed.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_row_ordinal;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;

RWStructuredBuffer<uint> call_arg_param_row;

static const uint INVALID = 0xffffffffu;
static const uint INTRINSIC_NONE = 0u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_arg_row_count()
{
    return min(call_arg_row_count_out[0u], active_hir_node_count());
}

uint active_param_row_count()
{
    return min(call_param_row_count_out[0u], active_hir_node_count());
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return INVALID;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint callee_token = callee.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(callee_token))
        callee_token = callee.token_start;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint method_param_offset(uint fn_i)
{
    uint mode = valid_token(fn_i) ? method_decl_receiver_mode[fn_i] : 0u;
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF ? 1u : 0u;
}

bool param_row_matches(uint row, uint fn_i, uint ordinal)
{
    return row < active_param_row_count() &&
           call_param_row_fn_token[row] == fn_i &&
           call_param_row_ordinal[row] == ordinal;
}

uint param_row_for_call_ordinal(uint call_node, uint arg_count, uint arg_ordinal)
{
    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) || call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return INVALID;

    uint fn_i = call_fn_index[callee_i];
    if (!valid_token(fn_i))
        return INVALID;

    uint param_count = call_param_count[fn_i];
    uint param_offset = method_param_offset(fn_i);
    uint expected_arg_count = param_count >= param_offset ? param_count - param_offset : 0u;
    if (arg_count == 0u || arg_count != expected_arg_count || param_offset >= param_count)
        return INVALID;

    uint start = call_param_row_start[fn_i];
    uint count = call_param_row_count[fn_i];
    uint param_ordinal = param_offset + arg_ordinal;
    uint row = start + param_ordinal;
    if (start == INVALID ||
        count == 0u ||
        param_ordinal >= count ||
        row < start ||
        row >= active_param_row_count())
        return INVALID;

    return param_row_matches(row, fn_i, param_ordinal) ? row : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint arg_rows = active_arg_row_count();
    if (row < arg_rows)
    {
        call_arg_param_row[row] = INVALID;

        uint call_node = call_arg_row_call_node[row];
        uint arg_count = valid_node(call_node) ? call_arg_row_count[call_node] : 0u;
        call_arg_param_row[row] = param_row_for_call_ordinal(
            call_node,
            arg_count,
            call_arg_row_ordinal[row]);
    }
}
