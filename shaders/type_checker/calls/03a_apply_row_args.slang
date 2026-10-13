// Apply row-dispatched generic direct call inference.

import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> call_generic_slot_type;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint PARAM_CACHE_STRIDE = 4u;
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
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty != INVALID;
}

uint plain_generic_slot(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty < TY_GENERIC_BASE + PARAM_CACHE_STRIDE
        ? ty - TY_GENERIC_BASE
        : INVALID;
}

uint array_or_slice_generic_slot(uint ty)
{
    return ty >= TY_ARRAY_BASE + TY_GENERIC_BASE &&
           ty < TY_ARRAY_BASE + TY_GENERIC_BASE + PARAM_CACHE_STRIDE
        ? ty - TY_ARRAY_BASE - TY_GENERIC_BASE
        : INVALID;
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = compact_hir_payload[call_node].a;
    return valid_node(callee_node) && compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
    {
        return valid_token(call_token) ? call_token : INVALID;
    }

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

void apply_row_argument_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;
    if (call_record_is_member_call(call_node))
        return;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        call_dependency_library_id[callee_i] != INVALID ||
        method_call_name_id[callee_i] != INVALID ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint fn_i = call_fn_index[callee_i];
    if (!valid_token(fn_i))
        return;

    uint generic_count = type_decl_generic_param_count[fn_i];
    if (generic_count == 0u)
        return;

    // This cache supplies provisional scalar facts only. Complete argument
    // claims and result contexts can bind parameters the cache cannot encode,
    // and dependent calls can refine them in later inference rounds. Required
    // slots are validated once, after that closure, from the complete relation.
    uint ret_ty = call_return_type[fn_i];
    uint current_ret_ty = call_return_type[callee_i];
    if (current_ret_ty != ret_ty && !is_generic_type(current_ret_ty))
        return;

    if (is_generic_type(ret_ty))
    {
        uint slot = plain_generic_slot(ret_ty);
        bool returns_array_or_slice_generic = slot == INVALID;
        if (returns_array_or_slice_generic)
            slot = array_or_slice_generic_slot(ret_ty);
        if (slot == INVALID || slot >= generic_count || slot >= PARAM_CACHE_STRIDE)
        {
            return;
        }

        uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
        uint inferred = call_generic_slot_type[state_i];
        if (inferred == INVALID)
        {
            call_return_type[callee_i] = TY_UNKNOWN;
            return;
        }
        call_return_type[callee_i] = returns_array_or_slice_generic
            ? TY_ARRAY_BASE + inferred
            : inferred;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    apply_row_argument_call(linear_thread_id(dtid));
}
