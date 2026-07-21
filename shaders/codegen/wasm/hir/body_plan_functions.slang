// Finalize per-function WASM body aggregates into global body-plan totals.
//
// This pass is deliberately token-domain only. Body collection has already
// reduced compact HIR rows into per-function semantic aggregates, so pulling
// the raw-tree body helper surface into this shader would retain parser inputs
// after their lifetime and dramatically enlarge the generated pipeline.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint artifact_flags;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> status;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
StructuredBuffer<uint> wasm_func_local_max_by_token;
StructuredBuffer<uint> wasm_func_return_count_by_token;
StructuredBuffer<uint> wasm_func_invalid_count_by_token;
StructuredBuffer<uint> wasm_func_return_token_by_token;
StructuredBuffer<uint> wasm_func_detail_by_token;
RWStructuredBuffer<uint> body_plan;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_ARRAY_BASE = 128u;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint BODY_PLAN_BODY_LEN_AGG = 32u;
static const uint BODY_PLAN_FUNCTION_INVALID_COUNT = 33u;
static const uint BODY_PLAN_MAIN_SLOT = 34u;
static const uint BODY_PLAN_STATUS = 0u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_DEBUG_SLOT_INVALID = 37u;
static const uint BODY_PLAN_DEBUG_MISSING_RETURN = 38u;
static const uint BODY_PLAN_DEBUG_UNSUPPORTED_SIGNATURE = 39u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool type_is_i32_value(uint ty)
{
    return ty == TY_BOOL || ty == TY_INT || ty == TY_UINT;
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value >>= 7u;
        if (value == 0u)
            return i + 1u;
    }
    return 5u;
}

uint local_decl_count_for_function_token(uint fn_token)
{
    if (!valid_token(fn_token))
        return 0u;
    uint local_max = wasm_func_local_max_by_token[fn_token];
    return local_max == INVALID ? 0u : local_max + 1u;
}

uint local_decl_fragment_len_from_count(uint local_count)
{
    if (local_count == 0u)
        return 1u;
    uint i32_count = local_count * 2u;
    return 1u + u32_leb_len(i32_count) + 1u + u32_leb_len(local_count) + 1u;
}

void publish_function_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_FUNCTION_INVALID_COUNT, 1u);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

bool wasm_function_signature_supported(uint fn_token)
{
    if (!valid_token(fn_token))
        return false;
    uint ret = call_return_type[fn_token];
    return ret == TY_VOID || type_is_i32_value(ret) || ret == TY_FLOAT || ret >= TY_ARRAY_BASE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;

    uint token_i = linear_dispatch_id(tid);
    if (!valid_token(token_i) || wasm_func_flag[token_i] == 0u)
        return;

    uint slot = wasm_func_slot_by_token[token_i];
    uint main_token = body_plan[BODY_PLAN_MAIN_TOKEN_MIN];
    if (slot == INVALID)
    {
        atomic_u32_add(body_plan, BODY_PLAN_DEBUG_SLOT_INVALID, 1u);
        if (token_i == main_token)
            publish_function_invalid(token_i);
        return;
    }

    if (token_i == main_token)
    {
        body_plan[BODY_PLAN_MAIN_SLOT] = slot;
        if (call_param_count[token_i] != 0u)
            publish_function_invalid(token_i);
    }

    uint detail = wasm_func_detail_by_token[token_i];
    if (wasm_func_invalid_count_by_token[token_i] != 0u)
    {
        publish_function_invalid(valid_token(detail) ? detail : token_i);
        return;
    }

    bool returns_void = call_return_type[token_i] == TY_VOID;
    if (!returns_void &&
        (wasm_func_return_count_by_token[token_i] == 0u ||
         !valid_token(wasm_func_return_token_by_token[token_i])))
    {
        atomic_u32_add(body_plan, BODY_PLAN_DEBUG_MISSING_RETURN, 1u);
        publish_function_invalid(token_i);
        return;
    }

    if (!wasm_function_signature_supported(token_i))
    {
        atomic_u32_add(body_plan, BODY_PLAN_DEBUG_UNSUPPORTED_SIGNATURE, 1u);
        publish_function_invalid(token_i);
        return;
    }

    uint local_count = local_decl_count_for_function_token(token_i);
    uint statement_len = wasm_func_body_len_by_token[token_i];
    uint end_len = returns_void ? 1u : 2u;
    uint body_size = local_decl_fragment_len_from_count(local_count) + statement_len + end_len;
    wasm_func_body_len_by_token[token_i] = body_size;
    atomic_u32_add(body_plan, BODY_PLAN_BODY_LEN_AGG, 5u + body_size);
}
