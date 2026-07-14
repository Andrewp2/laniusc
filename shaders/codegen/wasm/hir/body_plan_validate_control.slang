// Parallel validation and aggregate planning for scalar WASM control statements.

import atomics;
import body_common;
import body_plan_validate_common;

void validate_main_control(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    uint stmt_kind = stmt_record_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_NONE ||
        stmt_kind == STMT_RECORD_KIND_LET ||
        stmt_kind == STMT_RECORD_KIND_RETURN ||
        stmt_kind == STMT_RECORD_KIND_ASSIGN)
    {
        return;
    }

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_IF && hir_kind[node] == HIR_IF_STMT)
    {
        uint condition_record_node = stmt_record_slot(node, 1u);
        if (expr_contains_member(condition_record_node))
            return;
        uint raw_condition_node = resolve_expr_node(condition_record_node);
        if (valid_node(raw_condition_node) && expr_contains_member(raw_condition_node))
            return;
        if (valid_node(raw_condition_node) && !expr_contains_member(raw_condition_node))
            return;

        uint condition_node = INVALID;
        uint open_len = 0u;
        uint else_token = INVALID;
        uint else_len = 0u;
        uint end_token = INVALID;
        uint end_len = 0u;
        if (valid_node(raw_condition_node) && expr_contains_member(raw_condition_node))
        {
            condition_node = raw_condition_node;
            if (!if_end_token_and_len(node, end_token, end_len))
            {
                publish_func_invalid(owner_fn, token);
                return;
            }

            if (valid_node(stmt_record_slot(node, 3u)) &&
                !if_else_token_and_len(node, else_token, else_len))
            {
                publish_func_invalid(owner_fn, token);
                return;
            }

            uint condition_len = 0u;
            if (!expr_simple_and_len(condition_node, condition_len))
            {
                publish_func_invalid(owner_fn, token);
                return;
            }
            uint temp_len = condition_len + local_set_len(token);
            uint local_open_len = local_get_len(token) + 2u;
            add_func_local_token(owner_fn, token);
            add_func_body_len(owner_fn, temp_len + local_open_len + else_len + end_len);
            publish_fragment_slot(
                token * 2u,
                temp_len,
                uint4(BODY_FRAGMENT_LET_EXPR_I32, token, condition_node, token),
                uint4(INVALID, 0u, 0u, 0u));
            publish_fragment_slot(
                token * 2u + 1u,
                local_open_len,
                uint4(BODY_FRAGMENT_IF_OPEN_LOCAL_I32, token, local_open_len, token),
                uint4(INVALID, 0u, 0u, 0u));
            if (else_len != 0u)
            {
                publish_fragment(
                    else_token,
                    else_len,
                    uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token),
                    uint4(INVALID, 0u, 0u, 0u));
            }
            publish_fragment(
                end_token,
                end_len,
                uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token),
                uint4(INVALID, 0u, 0u, 0u));
            atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, end_token);
            return;
        }

        if (!if_open_fragment_and_len(node, condition_node, open_len) ||
            !if_end_token_and_len(node, end_token, end_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        if (valid_node(stmt_record_slot(node, 3u)) &&
            !if_else_token_and_len(node, else_token, else_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        add_func_body_len(owner_fn, open_len + else_len + end_len);
        publish_fragment(
            token,
            open_len,
            uint4(BODY_FRAGMENT_IF_OPEN_I32, condition_node, open_len, token),
            uint4(INVALID, 0u, 0u, 0u));
        if (else_len != 0u)
        {
            publish_fragment(
                else_token,
                else_len,
                uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token),
                uint4(INVALID, 0u, 0u, 0u));
        }
        publish_fragment(
            end_token,
            end_len,
            uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, end_token);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_WHILE && hir_kind[node] == HIR_WHILE_STMT)
    {
        uint condition_node = INVALID;
        uint open_len = 0u;
        uint close_token = INVALID;
        uint close_len = 0u;
        if (!while_open_fragment_and_len(node, condition_node, open_len) ||
            !while_close_token_and_len(node, close_token, close_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        if (expr_contains_member(condition_node))
        {
            uint condition_len = 0u;
            if (!expr_simple_and_len(condition_node, condition_len))
            {
                publish_func_invalid(owner_fn, token);
                return;
            }
            uint temp_len = condition_len + local_set_len(token);
            uint local_open_len = local_get_len(token) + 7u;
            add_func_local_token(owner_fn, token);
            add_func_body_len(owner_fn, temp_len + local_open_len + close_len);
            publish_fragment_slot(
                token * 2u,
                temp_len,
                uint4(BODY_FRAGMENT_LET_EXPR_I32, token, condition_node, token),
                uint4(INVALID, 0u, 0u, 0u));
            publish_fragment_slot(
                token * 2u + 1u,
                local_open_len,
                uint4(BODY_FRAGMENT_WHILE_OPEN_LOCAL_I32, token, local_open_len, token),
                uint4(INVALID, 0u, 0u, 0u));
            publish_fragment(
                close_token,
                close_len,
                uint4(BODY_FRAGMENT_WHILE_CLOSE, 0u, 0u, close_token),
                uint4(INVALID, 0u, 0u, 0u));
            atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, close_token);
            return;
        }
        add_func_body_len(owner_fn, open_len + close_len);
        publish_fragment(
            token,
            open_len,
            uint4(BODY_FRAGMENT_WHILE_OPEN_I32, condition_node, open_len, token),
            uint4(INVALID, 0u, 0u, 0u));
        publish_fragment(
            close_token,
            close_len,
            uint4(BODY_FRAGMENT_WHILE_CLOSE, 0u, 0u, close_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, close_token);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_FOR &&
        (hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT))
    {
        uint binding_token = INVALID;
        uint range_node = INVALID;
        uint end_local_token = INVALID;
        uint open_len = 0u;
        uint close_token = INVALID;
        uint close_len = 0u;
        if (!for_open_range_fragment_and_len(
                node,
                binding_token,
                range_node,
                end_local_token,
                open_len) ||
            !for_close_token_and_len(node, close_token, close_len))
        {
            uint iterable_node = resolve_expr_node(stmt_record_slot(node, 2u));
            if (valid_node(iterable_node) && expr_form(iterable_node) != HIR_EXPR_RANGE)
                return;
            publish_func_invalid(owner_fn, token);
            return;
        }
        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_local_token(owner_fn, hir_token_end[range_node]);
        add_func_body_len(owner_fn, open_len + close_len);
        publish_fragment(
            token,
            open_len,
            uint4(
                BODY_FRAGMENT_FOR_OPEN_RANGE_I32,
                binding_token,
                range_node,
                end_local_token),
            uint4(INVALID, 0u, 0u, 0u));
        publish_fragment(
            close_token,
            close_len,
            uint4(BODY_FRAGMENT_FOR_CLOSE_RANGE_I32, binding_token, close_len, close_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, close_token);
        return;
    }

    if ((stmt_kind == STMT_RECORD_KIND_BREAK && hir_kind[node] == HIR_BREAK_STMT) ||
        (stmt_kind == STMT_RECORD_KIND_CONTINUE && hir_kind[node] == HIR_CONTINUE_STMT))
    {
        uint depth = 0u;
        uint len = 0u;
        if (!loop_control_fragment_and_len(node, depth, len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        add_func_body_len(owner_fn, len);
        publish_fragment(
            token,
            len,
            uint4(BODY_FRAGMENT_BRANCH, depth, len, token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, token);
        return;
    }

    publish_func_invalid(owner_fn, token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;
    if (hir_kind[node] == HIR_ARRAY_EXPR || hir_kind[node] == HIR_CALL_EXPR)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_control(node, hir_token_pos[node]);
}
