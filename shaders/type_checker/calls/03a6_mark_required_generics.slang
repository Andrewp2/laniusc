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
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> type_decl_generic_param_count;

RWStructuredBuffer<uint> call_required_generic_scan_input;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
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
    return gParams.n_hir_nodes == 0u
        ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint callee_token = callee.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(callee_token))
        callee_token = callee.token_start;
    if (!valid_token(callee_token))
        callee_token = call_token;
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = compact_hir_payload[call_node].a;
    return valid_node(callee_node) &&
        compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR;
}

uint required_generic_count_for_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
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
