// Parallel validation and aggregate planning for the scalar WASM body.

import atomics;
import body_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;

static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_MAIN_TOKEN_MIN = 9u;
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

void publish_detail(uint detail)
{
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
}

void publish_stmt_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_STMT_INVALID_COUNT, 1u);
    publish_detail(detail);
}

void publish_call_invalid(uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_CALL_INVALID_COUNT, 1u);
    publish_detail(detail);
}

void publish_return_value(uint value)
{
    uint old_value = 0u;
    InterlockedExchange(body_plan[BODY_PLAN_RETURN_VALUE_AGG], value, old_value);
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
}

void validate_main_statement(uint node, uint token)
{
    uint stmt_kind = stmt_record_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_NONE)
        return;

    if (!valid_token(token))
    {
        publish_stmt_invalid(INVALID);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_LET && hir_kind[node] == HIR_LET_STMT)
    {
        atomic_u32_add(body_plan, BODY_PLAN_LET_COUNT, 1u);
        atomic_u32_max(body_plan, BODY_PLAN_LET_MAX_TOKEN, token);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_RETURN && hir_kind[node] == HIR_RETURN_STMT)
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_COUNT, 1u);
        atomic_u32_min(body_plan, BODY_PLAN_RETURN_TOKEN_MIN, token);

        uint return_expr = stmt_record_slot(node, 1u);
        uint return_value = 0u;
        if (valid_node(return_expr) &&
            hir_kind[return_expr] == HIR_EXPR &&
            const_expr_value(return_expr, return_value))
        {
            publish_return_value(return_value);
        }
        else
        {
            atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_INVALID_COUNT, 1u);
            publish_detail(token);
        }
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_IF && hir_kind[node] == HIR_IF_STMT)
    {
        uint condition = 0u;
        if (!if_condition_value(node, condition))
        {
            publish_stmt_invalid(token);
            return;
        }

        uint then_block = stmt_record_slot(node, 2u);
        if (!valid_node(then_block))
        {
            publish_stmt_invalid(token);
            return;
        }
        return;
    }

    publish_stmt_invalid(token);
}

void validate_main_call(uint node, uint token)
{
    if (!valid_token(token))
    {
        publish_call_invalid(INVALID);
        return;
    }

    uint value = 0u;
    uint len = 0u;
    if (!print_call_node(node) || !print_call_value_and_len(node, value, len))
    {
        publish_call_invalid(token);
        return;
    }

    atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
    atomic_u32_add(body_plan, BODY_PLAN_PRINT_LEN_AGG, len);
    atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] != 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint main_token = body_plan[BODY_PLAN_MAIN_TOKEN_MIN];
    if (!valid_token(main_token) || node_enclosing_fn_token(node) != main_token)
        return;
    if (!node_enabled_by_constant_if_chain(node))
        return;

    uint token = hir_token_pos[node];
    validate_main_statement(node, token);

    if (hir_kind[node] == HIR_CALL_EXPR)
        validate_main_call(node, token);
}
