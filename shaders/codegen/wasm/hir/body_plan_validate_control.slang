// Parallel validation and aggregate planning for scalar WASM control statements.

import atomics;
import body_common;
import body_plan_validate_common;

StructuredBuffer<uint> hir_nearest_loop_node;
StructuredBuffer<int> if_depth;

bool loop_control_fragment_and_len(uint node, out uint depth, out uint len)
{
    depth = 0u;
    len = 0u;
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_BREAK_STMT && hir_kind[node] != HIR_CONTINUE_STMT))
    {
        return false;
    }

    uint stmt_kind = stmt_record_slot(node, 0u);
    if ((hir_kind[node] == HIR_BREAK_STMT && stmt_kind != STMT_RECORD_KIND_BREAK) ||
        (hir_kind[node] == HIR_CONTINUE_STMT && stmt_kind != STMT_RECORD_KIND_CONTINUE))
    {
        return false;
    }

    uint loop_node = hir_nearest_loop_node[node];
    if (!valid_node(loop_node))
        return false;
    uint loop_kind = hir_kind[loop_node];
    uint loop_stmt_kind = stmt_record_slot(loop_node, 0u);
    if ((loop_kind != HIR_WHILE_STMT || loop_stmt_kind != STMT_RECORD_KIND_WHILE) &&
        (loop_kind != HIR_FOR_STMT || loop_stmt_kind != STMT_RECORD_KIND_FOR))
    {
        return false;
    }

    uint token = hir_token_pos[node];
    uint loop_token = hir_token_pos[loop_node];
    if (!valid_token(token) || !valid_token(loop_token))
        return false;
    int branch_if_depth = if_depth[token];
    int loop_if_depth = if_depth[loop_token];
    if (branch_if_depth < loop_if_depth)
        return false;

    depth = uint(branch_if_depth - loop_if_depth);
    if (hir_kind[node] == HIR_BREAK_STMT)
        depth += loop_kind == HIR_FOR_STMT ? 2u : 1u;
    len = 1u + u32_leb_len(depth);
    return true;
}

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
        // Scalar IF planning is owned by body_plan_validate, which sizes the
        // condition from the parallel expression forest. This pass owns only
        // loop control and must not classify the same statement a second time.
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_WHILE && hir_kind[node] == HIR_WHILE_STMT)
    {
        uint condition_node = resolve_expr_node(stmt_record_slot(node, 1u));
        uint2 condition_total = valid_node(condition_node)
                                    ? expr_subtree_total[condition_node]
                                    : uint2(0u, 1u);
        uint close_token = INVALID;
        uint close_len = 0u;
        if (condition_total.y != 0u || condition_total.x == 0u ||
            !while_close_token_and_len(node, close_token, close_len))
        {
            publish_func_invalid(owner_fn, token);
            return;
        }
        uint open_len = condition_total.x + 7u;
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
        atomic_u32_or(
            body_plan,
            BODY_PLAN_FEATURE_MASK,
            BODY_FEATURE_MEMBER_EXPR_SCATTER);
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
