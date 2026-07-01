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

void publish_function_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_FUNCTION_INVALID_COUNT, 1u);
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
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
    if (slot == INVALID)
    {
        publish_function_invalid(token_i);
        return;
    }

    uint main_token = body_plan[BODY_PLAN_MAIN_TOKEN_MIN];
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

    if (wasm_func_return_count_by_token[token_i] == 0u ||
        !valid_token(wasm_func_return_token_by_token[token_i]))
    {
        publish_function_invalid(token_i);
        return;
    }

    uint param_count = call_param_count[token_i];
    if (param_count > WASM_MAX_DIRECT_CALL_ARGS)
    {
        publish_function_invalid(token_i);
        return;
    }

    for (uint i = 0u; i < WASM_MAX_DIRECT_CALL_ARGS; i += 1u)
    {
        if (i < param_count && call_param_type_value(token_i, i) != TY_INT)
        {
            publish_function_invalid(token_i);
            return;
        }
    }

    uint local_count = local_decl_count_for_function_token(token_i);
    uint statement_len = wasm_func_body_len_by_token[token_i];
    uint body_size = local_decl_fragment_len_from_count(local_count) + statement_len + 2u;
    wasm_func_body_len_by_token[token_i] = body_size;
    atomic_u32_add(body_plan, BODY_PLAN_BODY_LEN_AGG, 5u + body_size);
}
