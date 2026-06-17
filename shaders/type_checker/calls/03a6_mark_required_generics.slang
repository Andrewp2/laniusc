// Mark per-call required generic-parameter rows.
//
// Each direct call contributes one validation relation per declared function
// generic parameter. The following scan gives each call a compact requirement
// span so validation can run one thread per required slot instead of unrolling
// a fixed cache width in the call thread.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> type_decl_generic_param_count;

RWStructuredBuffer<uint> call_required_generic_scan_input;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint expr_value_token(uint node)
{
    return valid_node(node)
        ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + HIR_EXPR_RECORD_VALUE_TOKEN]
        : INVALID;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = hir_token_pos[call_node];
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expr_value_token(callee_node);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[call_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = hir_call_callee_node[call_node];
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR;
}

uint required_generic_count_for_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return 0u;
    if (call_record_is_member_call(call_node))
        return 0u;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        method_call_name_id[callee_i] != INVALID ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return 0u;

    uint fn_i = call_fn_index[callee_i];
    return valid_token(fn_i) ? type_decl_generic_param_count[fn_i] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;

    call_required_generic_scan_input[node] = required_generic_count_for_call(node);
}
