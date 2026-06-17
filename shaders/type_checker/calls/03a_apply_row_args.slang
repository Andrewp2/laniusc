// Apply row-dispatched generic direct call inference.

import status;

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
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> call_generic_slot_ordinal;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
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

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
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

uint expr_value_token(uint node)
{
    return valid_node(node)
        ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + HIR_EXPR_RECORD_VALUE_TOKEN]
        : INVALID;
}

bool call_record_is_member_call(uint call_node)
{
    if (!valid_node(call_node))
        return false;
    uint callee_node = hir_call_callee_node[call_node];
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = hir_token_pos[call_node];
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
    {
        return valid_token(call_token) ? call_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expr_value_token(callee_node);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[call_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

bool check_required_generic_slot(uint callee_i, uint generic_count, uint slot)
{
    if (slot >= generic_count)
        return true;

    uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
    uint inferred = call_generic_slot_type[state_i];
    if (inferred != INVALID)
        return true;

    if (call_generic_slot_ordinal[state_i] != INVALID)
        return false;

    record_error(
        callee_i,
        ERR_ASSIGN_MISMATCH,
        (TY_GENERIC_BASE + slot) * 256u + TY_UNKNOWN);
    return false;
}

void apply_row_argument_call(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;
    if (call_record_is_member_call(call_node))
        return;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        method_call_name_id[callee_i] != INVALID ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint fn_i = call_fn_index[callee_i];
    uint arg_count = call_arg_row_count[call_node];
    if (!valid_token(fn_i))
        return;

    uint generic_count = type_decl_generic_param_count[fn_i];
    if (generic_count == 0u)
        return;

    if (!check_required_generic_slot(callee_i, generic_count, 0u) ||
        !check_required_generic_slot(callee_i, generic_count, 1u) ||
        !check_required_generic_slot(callee_i, generic_count, 2u) ||
        !check_required_generic_slot(callee_i, generic_count, 3u))
    {
        call_return_type[callee_i] = TY_UNKNOWN;
        return;
    }

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
            record_error(callee_i, ERR_ASSIGN_MISMATCH, ret_ty * 256u + TY_UNKNOWN);
            call_return_type[callee_i] = TY_UNKNOWN;
            return;
        }

        uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
        uint inferred = call_generic_slot_type[state_i];
        if (inferred == INVALID)
        {
            if (call_generic_slot_ordinal[state_i] == INVALID)
                record_error(callee_i, ERR_ASSIGN_MISMATCH, ret_ty * 256u + TY_UNKNOWN);
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
