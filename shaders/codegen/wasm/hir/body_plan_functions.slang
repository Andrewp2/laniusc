// Finalize per-function WASM body aggregates into global body-plan totals.

import atomics;
import body_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;

static const uint BODY_PLAN_BODY_LEN_AGG = 32u;
static const uint BODY_PLAN_FUNCTION_INVALID_COUNT = 33u;
static const uint BODY_PLAN_MAIN_SLOT = 34u;
static const uint BODY_PLAN_STATUS = 0u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_DEBUG_SLOT_INVALID = 37u;
static const uint BODY_PLAN_DEBUG_MISSING_RETURN = 38u;
static const uint BODY_PLAN_DEBUG_UNSUPPORTED_SIGNATURE = 39u;

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
