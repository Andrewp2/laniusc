// Parallel validation and aggregate planning for scalar WASM let statements.

import atomics;
import body_common;
import body_plan_validate_common;

void validate_main_let(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] == HIR_NONE)
        return;

    uint stmt_kind = stmt_record_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_NONE || hir_kind[node] == HIR_ARRAY_EXPR)
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_LET && hir_kind[node] == HIR_LET_STMT)
    {
        uint raw_init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
        if (valid_node(raw_init_expr) && hir_kind[raw_init_expr] == HIR_ARRAY_EXPR)
            return;
        uint raw_decl_token = stmt_record_slot(node, 1u);
        if (valid_token(raw_decl_token) && wasm_agg_local_width_by_token[raw_decl_token] != 0u)
            return;
        if (valid_token(raw_decl_token) &&
            visible_type_for_token(raw_decl_token) >= TY_ARRAY_BASE &&
            valid_node(raw_init_expr) &&
            hir_kind[raw_init_expr] == HIR_CALL_EXPR)
        {
            return;
        }
        if (valid_node(raw_init_expr) && hir_kind[raw_init_expr] == HIR_CALL_EXPR)
            return;
        if (valid_node(raw_init_expr) && expr_binary_op_supported(expr_form(raw_init_expr)))
        {
            uint raw_left = resolve_expr_node(expr_record_slot(raw_init_expr, EXPR_RECORD_LEFT));
            uint raw_right = resolve_expr_node(expr_record_slot(raw_init_expr, EXPR_RECORD_RIGHT));
            if ((valid_node(raw_left) && hir_kind[raw_left] == HIR_CALL_EXPR) ||
                (valid_node(raw_right) && hir_kind[raw_right] == HIR_CALL_EXPR))
            {
                return;
            }
        }

        uint decl_token = INVALID;
        uint expr_node = INVALID;
        uint value = 0u;
        uint len = 0u;
        uint4 aux = uint4(INVALID, 0u, 0u, 0u);
        uint kind = BODY_FRAGMENT_LET_CONST_I32;
        uint meta_w = token;
        bool runtime_expr = true;
        if (supported_let_const_fragment(node, decl_token, value, len))
        {
            runtime_expr = false;
            kind = BODY_FRAGMENT_LET_CONST_I32;
            expr_node = value;
        }
        else if (supported_let_expr_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_EXPR_I32;
        }
        else
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        uint init_expr = stmt_record_slot(node, 2u);
        if (!runtime_expr && expr_mentions_local_let(init_expr))
            atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);

        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_body_len(owner_fn, len);
        publish_fragment(token, len, uint4(kind, decl_token, expr_node, meta_w), aux);
        return;
    }

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

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    uint token = hir_token_pos[node];
    validate_main_let(node, token);
}
