// Finalize WASM body-plan aggregate records with lane-per-slot publication.

import body_common;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> status;

static const uint BODY_PLAN_INVALID = 0u;
static const uint BODY_PLAN_OK = 1u;
static const uint BODY_PLAN_STATUS = 0u;
static const uint BODY_PLAN_MAIN_TOKEN = 1u;
static const uint BODY_PLAN_RETURN_TOKEN = 2u;
static const uint BODY_PLAN_BODY_LEN = 3u;
static const uint BODY_PLAN_RETURN_VALUE = 4u;
static const uint BODY_PLAN_PRINT_COUNT = 5u;
static const uint BODY_PLAN_PRINT_LEN = 6u;
static const uint BODY_PLAN_DETAIL = 7u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
static const uint BODY_PLAN_COLLECT_INVALID_COUNT = 10u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_RETURN_COUNT = 12u;
static const uint BODY_PLAN_RETURN_TOKEN_MIN = 13u;
static const uint BODY_PLAN_LET_COUNT = 14u;
static const uint BODY_PLAN_LET_MAX_TOKEN = 15u;
static const uint BODY_PLAN_CALL_INVALID_COUNT = 16u;
static const uint BODY_PLAN_PRINT_COUNT_AGG = 17u;
static const uint BODY_PLAN_PRINT_LEN_AGG = 18u;
static const uint BODY_PLAN_PRINT_MAX_TOKEN = 19u;
static const uint BODY_PLAN_RETURN_VALUE_OK_COUNT = 20u;
static const uint BODY_PLAN_RETURN_VALUE_AGG = 21u;
static const uint BODY_PLAN_RETURN_VALUE_INVALID_COUNT = 22u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_ASSIGN_COUNT = 24u;
static const uint BODY_PLAN_ASSIGN_MAX_TOKEN = 25u;
static const uint BODY_PLAN_ASSIGN_LEN_AGG = 26u;
static const uint BODY_PLAN_LET_LEN_AGG = 27u;
static const uint BODY_PLAN_RETURN_LEN_AGG = 28u;
static const uint BODY_PLAN_LOCAL_CONST_EXPR_COUNT = 29u;
static const uint BODY_PLAN_CONTROL_LEN_AGG = 30u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint BODY_PLAN_BODY_LEN_AGG = 32u;
static const uint BODY_PLAN_FUNCTION_INVALID_COUNT = 33u;
static const uint BODY_PLAN_MAIN_SLOT = 34u;
static const uint BODY_PLAN_FINALIZE_SLOT_COUNT = 15u;

uint base_fallback_detail(uint main_token, uint return_token, uint detail)
{
    if (valid_token(detail))
        return detail;
    if (valid_token(return_token))
        return return_token;
    if (valid_token(main_token))
        return main_token;
    return INVALID;
}

uint plan_error_detail(uint main_token, uint return_token, uint print_count, uint assign_count)
{
    uint detail = body_plan[BODY_PLAN_ERROR_DETAIL_MIN];
    if (body_plan[BODY_PLAN_LET_COUNT] != 0u &&
        body_plan[BODY_PLAN_LET_MAX_TOKEN] >= return_token)
        detail = min(detail, body_plan[BODY_PLAN_LET_MAX_TOKEN]);
    if (assign_count != 0u && body_plan[BODY_PLAN_ASSIGN_MAX_TOKEN] >= return_token)
        detail = min(detail, body_plan[BODY_PLAN_ASSIGN_MAX_TOKEN]);
    if (print_count != 0u && body_plan[BODY_PLAN_PRINT_MAX_TOKEN] >= return_token)
        detail = min(detail, body_plan[BODY_PLAN_PRINT_MAX_TOKEN]);
    return base_fallback_detail(main_token, return_token, detail);
}

bool plan_aggregate_ok(
    uint main_token,
    uint return_token,
    uint let_count,
    uint let_max_token,
    uint let_len,
    uint assign_count,
    uint assign_len,
    uint control_len,
    uint print_count,
    uint print_len,
    uint return_len,
    uint local_const_expr_count,
    out uint body_len)
{
    body_len = 0u;
    if (body_plan[BODY_PLAN_MAIN_COUNT] != 1u)
        return false;
    if (body_plan[BODY_PLAN_FUNCTION_COUNT] == 0u)
        return false;
    if (body_plan[BODY_PLAN_FUNCTION_INVALID_COUNT] != 0u)
        return false;
    if (body_plan[BODY_PLAN_COLLECT_INVALID_COUNT] != 0u)
        return false;
    if (!valid_token(main_token))
        return false;
    if (body_plan[BODY_PLAN_STMT_INVALID_COUNT] != 0u)
        return false;
    if (body_plan[BODY_PLAN_RETURN_VALUE_INVALID_COUNT] != 0u)
        return false;
    if (body_plan[BODY_PLAN_CALL_INVALID_COUNT] != 0u)
        return false;
    if (assign_count != 0u && local_const_expr_count != 0u)
        return false;
    if (body_plan[BODY_PLAN_BODY_LEN_AGG] == 0u)
        return false;

    body_len = body_plan[BODY_PLAN_BODY_LEN_AGG];
    return body_len <= gParams.out_capacity;
}

uint final_body_plan_word(
    uint slot,
    bool hard_error,
    bool ok,
    uint main_token,
    uint return_token,
    uint print_count,
    uint print_len,
    uint return_value,
    uint body_len,
    uint detail)
{
    if (hard_error)
    {
        if (slot == BODY_PLAN_STATUS) return BODY_PLAN_INVALID;
        if (slot == BODY_PLAN_MAIN_TOKEN) return INVALID;
        if (slot == BODY_PLAN_RETURN_TOKEN) return INVALID;
        if (slot == BODY_PLAN_BODY_LEN) return 0u;
        if (slot == BODY_PLAN_RETURN_VALUE) return 0u;
        if (slot == BODY_PLAN_PRINT_COUNT) return 0u;
        if (slot == BODY_PLAN_PRINT_LEN) return 0u;
        if (slot == BODY_PLAN_DETAIL) return INVALID;
    }

    if (ok)
    {
        if (slot == BODY_PLAN_STATUS) return BODY_PLAN_OK;
        if (slot == BODY_PLAN_MAIN_TOKEN) return main_token;
        if (slot == BODY_PLAN_RETURN_TOKEN) return return_token;
        if (slot == BODY_PLAN_BODY_LEN) return body_len;
        if (slot == BODY_PLAN_RETURN_VALUE) return return_value;
        if (slot == BODY_PLAN_PRINT_COUNT) return print_count;
        if (slot == BODY_PLAN_PRINT_LEN) return print_len;
        if (slot == BODY_PLAN_DETAIL) return INVALID;
    }

    if (slot == BODY_PLAN_STATUS) return BODY_PLAN_INVALID;
    if (slot == BODY_PLAN_MAIN_TOKEN) return main_token;
    if (slot == BODY_PLAN_RETURN_TOKEN) return return_token;
    if (slot == BODY_PLAN_BODY_LEN) return 0u;
    if (slot == BODY_PLAN_RETURN_VALUE) return 0u;
    if (slot == BODY_PLAN_PRINT_COUNT) return 0u;
    if (slot == BODY_PLAN_PRINT_LEN) return 0u;
    if (slot == BODY_PLAN_DETAIL) return detail;
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = linear_dispatch_id(tid);
    uint input_error_code = status[2u];
    GroupMemoryBarrierWithGroupSync();

    uint main_token = body_plan[BODY_PLAN_MAIN_TOKEN_MIN];
    uint return_token = body_plan[BODY_PLAN_RETURN_TOKEN_MIN];
    uint let_count = body_plan[BODY_PLAN_LET_COUNT];
    uint let_max_token = body_plan[BODY_PLAN_LET_MAX_TOKEN];
    uint let_len = body_plan[BODY_PLAN_LET_LEN_AGG];
    uint assign_count = body_plan[BODY_PLAN_ASSIGN_COUNT];
    uint assign_len = body_plan[BODY_PLAN_ASSIGN_LEN_AGG];
    uint control_len = body_plan[BODY_PLAN_CONTROL_LEN_AGG];
    uint print_count = body_plan[BODY_PLAN_PRINT_COUNT_AGG];
    uint print_len = body_plan[BODY_PLAN_PRINT_LEN_AGG];
    uint return_value = body_plan[BODY_PLAN_RETURN_VALUE_AGG];
    uint return_len = body_plan[BODY_PLAN_RETURN_LEN_AGG];
    uint local_const_expr_count = body_plan[BODY_PLAN_LOCAL_CONST_EXPR_COUNT];
    uint body_len = 0u;
    bool ok = plan_aggregate_ok(
        main_token,
        return_token,
        let_count,
        let_max_token,
        let_len,
        assign_count,
        assign_len,
        control_len,
        print_count,
        print_len,
        return_len,
        local_const_expr_count,
        body_len);
    bool hard_error =
        input_error_code != 0u &&
        input_error_code != ERR_UNSUPPORTED_SOURCE_SHAPE;
    uint detail = plan_error_detail(main_token, return_token, print_count, assign_count);

    if (slot < 8u)
    {
        body_plan[slot] = final_body_plan_word(
            slot,
            hard_error,
            ok,
            main_token,
            return_token,
            print_count,
            print_len,
            return_value,
            body_len,
            detail);
        return;
    }

    if (slot >= 8u && slot < 12u && !hard_error)
    {
        uint body_status_slot = slot - 8u;
        body_status[body_status_slot] =
            body_status_slot == 3u ? INVALID : 0u;
        return;
    }

    if (slot >= 12u && slot < BODY_PLAN_FINALIZE_SLOT_COUNT && !hard_error)
    {
        uint status_slot = slot - 11u;
        if (status_slot == 1u)
            status[1u] = 0u;
        else if (status_slot == 2u)
            status[2u] = ok ? 0u : ERR_UNSUPPORTED_SOURCE_SHAPE;
        else
            status[3u] = ok ? INVALID : detail;
    }
}
