// Row-state generic array/slice call return inference.
//
// This pass runs after call resolution, visible-declaration projection, and
// row-dispatched generic argument collection. It handles call shapes:
//   fn first<T, const N: usize>(values: [T; N]) -> T
// or:
//   fn first_slice<T>(values: [T]) -> T
// plus matching array/slice identifier returns:
//   fn copy<T, const N: usize>(values: [T; N]) -> [T; N]
// It consumes the compact row inference state; it does not inspect source
// bytes, token spellings, token kinds, helper names, or function bodies.

import status;

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
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> method_call_name_id;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TY_ARRAY_BASE = 128u;

static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;
static const uint PARAM_CACHE_STRIDE = 4u;
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

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return INVALID;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint callee_token = callee.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(callee_token)) callee_token = callee.token_start;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_node_for_callee_token(uint callee_token)
{
    return valid_token(callee_token) ? call_arg_record[callee_token].z : INVALID;
}

uint call_arg_count_for_callee(uint callee_token, uint call_node)
{
    if (!valid_token(callee_token))
        return 0u;
    uint record_count = call_arg_record[callee_token].w;
    if (!valid_node(call_node))
        return record_count;
    return max(max(record_count, compact_hir_payload[call_node].c), call_arg_row_count[call_node]);
}

bool check_call_window(
    uint callee_token,
    uint call_node,
    uint fn_token,
    out uint param_count,
    out uint arg_count)
{
    param_count = valid_token(fn_token) ? call_param_count[fn_token] : 0u;
    arg_count = call_arg_count_for_callee(callee_token, call_node);
    bool param_metadata_matches = param_count == 0u || param_count == arg_count;
    if (param_metadata_matches)
        return true;

    call_return_type[callee_token] = TY_UNKNOWN;
    record_min_token_error(
        status,
        callee_token,
        ERR_CALL_MISMATCH,
        CALL_MISMATCH_ARITY);
    return false;
}

bool plain_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty < TY_GENERIC_BASE + PARAM_CACHE_STRIDE;
}

uint plain_generic_slot(uint ty)
{
    return plain_generic_type(ty) ? ty - TY_GENERIC_BASE : INVALID;
}

uint array_or_slice_generic_slot(uint ty)
{
    return ty >= TY_ARRAY_BASE + TY_GENERIC_BASE &&
           ty < TY_ARRAY_BASE + TY_GENERIC_BASE + PARAM_CACHE_STRIDE
               ? ty - TY_ARRAY_BASE - TY_GENERIC_BASE
               : INVALID;
}

void infer_array_generic_return(uint callee_token)
{
    if (!valid_token(callee_token))
        return;

    uint call_node = call_node_for_callee_token(callee_token);
    if (!valid_node(call_node))
        return;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token))
        return;

    uint ret_ty = call_return_type[callee_token];
    if (ret_ty == TY_UNKNOWN)
        ret_ty = call_return_type[fn_token];
    if (ret_ty != TY_ARRAY_BASE + TY_UNKNOWN &&
        plain_generic_slot(ret_ty) == INVALID &&
        array_or_slice_generic_slot(ret_ty) == INVALID)
        return;

    uint param_count = 0u;
    uint arg_count = 0u;
    if (!check_call_window(callee_token, call_node, fn_token, param_count, arg_count))
        return;

    uint ret_slot = plain_generic_slot(ret_ty);
    if (ret_slot != INVALID)
    {
        uint inferred = call_generic_slot_type[callee_token * PARAM_CACHE_STRIDE + ret_slot];
        if (inferred != INVALID)
        {
            call_return_type[callee_token] = inferred;
            return;
        }
        return;
    }

    uint ret_array_slot = array_or_slice_generic_slot(ret_ty);
    if (ret_array_slot == INVALID)
        return;
    uint inferred = call_generic_slot_type[callee_token * PARAM_CACHE_STRIDE + ret_array_slot];
    if (inferred != INVALID)
    {
        call_return_type[callee_token] = TY_ARRAY_BASE + inferred;
        return;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint callee_token = linear_thread_id(dtid);
    if (!valid_token(callee_token))
        return;
    if (method_call_name_id[callee_token] != INVALID)
        return;

    infer_array_generic_return(callee_token);
}
