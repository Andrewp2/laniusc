// Parallel validation and aggregate planning for scalar WASM return statements.

import atomics;
import body_common;
import body_plan_validate_common;

bool return_call_candidate(uint stmt_node)
{
    if (!valid_node(stmt_node) ||
        hir_kind[stmt_node] != HIR_RETURN_STMT ||
        stmt_record_slot(stmt_node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    uint expr_node = resolve_expr_node(stmt_record_slot(stmt_node, 1u));
    if (!valid_node(expr_node))
        return false;
    if (hir_kind[expr_node] == HIR_CALL_EXPR)
        return true;

    uint form = expr_form(expr_node);
    if (!expr_binary_op_supported(form))
        return false;
    uint left = resolve_expr_node(expr_record_slot(expr_node, EXPR_RECORD_LEFT));
    uint right = resolve_expr_node(expr_record_slot(expr_node, EXPR_RECORD_RIGHT));
    return (valid_node(left) && hir_kind[left] == HIR_CALL_EXPR) ||
           (valid_node(right) && hir_kind[right] == HIR_CALL_EXPR);
}

bool direct_member_expr(uint node)
{
    node = resolve_expr_node(node);
    return valid_node(node) && hir_kind[node] == HIR_MEMBER_EXPR;
}

void validate_main_return(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_RETURN_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return;
    }

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    atomic_u32_add(wasm_func_return_count_by_token, owner_fn, 1u);
    atomic_u32_min(wasm_func_return_token_by_token, owner_fn, token);
    if (return_call_candidate(node))
        return;
    uint raw_expr = stmt_record_slot(node, 1u);
    if (call_return_type[owner_fn] >= TY_ARRAY_BASE)
    {
        uint local_decl = INVALID;
        if (!local_decl_token_for_name_expr(raw_expr, local_decl))
            return;
    }
    uint resolved_expr = resolve_expr_node(raw_expr);
    if ((valid_node(raw_expr) && hir_kind[raw_expr] == HIR_STRUCT_LITERAL_EXPR) ||
        (valid_node(resolved_expr) && hir_kind[resolved_expr] == HIR_STRUCT_LITERAL_EXPR))
        return;

    uint return_expr_node = INVALID;
    uint return_value = 0u;
    uint return_len = 0u;
    if (return_expr_local_and_len(node, return_expr_node, return_len))
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
        add_func_body_len(owner_fn, return_len);
        publish_fragment(
            token,
            return_len,
            uint4(BODY_FRAGMENT_RETURN_LOCAL_I32, return_expr_node, return_len, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (return_expr_value_and_len(node, return_value, return_len))
    {
        publish_return_value(return_value);
        add_func_body_len(owner_fn, return_len);
        if (expr_mentions_local_let(stmt_record_slot(node, 1u)))
            atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);
        publish_fragment(
            token,
            return_len,
            uint4(BODY_FRAGMENT_RETURN_I32, return_value, return_len, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (return_expr_fragment_and_len(node, return_expr_node, return_len))
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
        add_func_body_len(owner_fn, return_len);
        if (direct_member_expr(return_expr_node))
            publish_body_features(BODY_FEATURE_RETURN_MEMBER_EXPR);
        publish_fragment(
            token,
            return_len,
            uint4(BODY_FRAGMENT_RETURN_EXPR_I32, return_expr_node, return_len, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_INVALID_COUNT, 1u);
        publish_func_invalid(owner_fn, token);
    }
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

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_return(node, hir_token_pos[node]);
}
