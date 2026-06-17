// Seed compact argument-to-parameter list matching.
//
// This is the first phase of a Hillis-Steele linked-list match over compact
// call-argument rows and compact function-parameter rows. It initializes each
// list's one-step jump pointer and seeds the first argument of each resolved
// call with the first matching parameter row.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_name_token;
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
RWStructuredBuffer<uint> call_arg_match_jump_a;
RWStructuredBuffer<uint> call_param_match_jump_a;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    uint callee_token = hir_kind[callee_node] == HIR_MEMBER_EXPR
        ? hir_member_name_token[callee_node]
        : hir_token_pos[callee_node];
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

uint first_param_row_for_call(uint call_node, uint arg_count)
{
    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) || call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return INVALID;

    uint fn_i = call_fn_index[callee_i];
    if (!valid_token(fn_i))
        return INVALID;

    uint param_count = call_param_count[fn_i];
    uint param_offset = method_call_name_id[callee_i] != INVALID ? method_param_offset(fn_i) : 0u;
    uint expected_arg_count = param_count >= param_offset ? param_count - param_offset : 0u;
    if (arg_count == 0u || arg_count != expected_arg_count || param_offset >= param_count)
        return INVALID;

    uint start = call_param_row_start[fn_i];
    uint count = call_param_row_count[fn_i];
    uint row = start + param_offset;
    if (start == INVALID ||
        count == 0u ||
        param_offset >= count ||
        row < start ||
        row >= active_param_row_count())
        return INVALID;

    return param_row_matches(row, fn_i, param_offset) ? row : INVALID;
}

uint next_arg_row(uint row)
{
    if (row >= active_arg_row_count())
        return INVALID;
    uint call_node = call_arg_row_call_node[row];
    uint ordinal = call_arg_row_ordinal[row];
    if (!valid_node(call_node))
        return INVALID;
    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    uint next = row + 1u;
    if (start == INVALID ||
        ordinal == INVALID ||
        ordinal + 1u >= count ||
        next < start ||
        next >= active_arg_row_count() ||
        call_arg_row_call_node[next] != call_node ||
        call_arg_row_ordinal[next] != ordinal + 1u)
        return INVALID;
    return next;
}

uint next_param_row(uint row)
{
    if (row >= active_param_row_count())
        return INVALID;
    uint fn_i = call_param_row_fn_token[row];
    uint ordinal = call_param_row_ordinal[row];
    if (!valid_token(fn_i))
        return INVALID;
    uint start = call_param_row_start[fn_i];
    uint count = call_param_row_count[fn_i];
    uint next = row + 1u;
    if (start == INVALID ||
        ordinal == INVALID ||
        ordinal + 1u >= count ||
        next < start ||
        next >= active_param_row_count() ||
        call_param_row_fn_token[next] != fn_i ||
        call_param_row_ordinal[next] != ordinal + 1u)
        return INVALID;
    return next;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint arg_rows = active_arg_row_count();
    uint param_rows = active_param_row_count();

    if (row < arg_rows)
    {
        call_arg_param_row[row] = INVALID;
        call_arg_match_jump_a[row] = next_arg_row(row);

        if (call_arg_row_ordinal[row] == 0u)
        {
            uint call_node = call_arg_row_call_node[row];
            uint arg_count = valid_node(call_node) ? call_arg_row_count[call_node] : 0u;
            call_arg_param_row[row] = first_param_row_for_call(call_node, arg_count);
        }
    }

    if (row < param_rows)
        call_param_match_jump_a[row] = next_param_row(row);
}
