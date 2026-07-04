// Parallel validation and aggregate planning for statement-position calls.

import atomics;
import body_common;
import body_plan_validate_common;

void validate_main_call(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!statement_position_call(node))
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    uint len = 0u;
    uint decl_token = INVALID;
    uint expr_node = INVALID;
    uint value = 0u;
    if (supported_host_void_call_fragment(
            node,
            LANGUAGE_SYMBOL_DEALLOC,
            WASM_DEALLOC_FUNC_INDEX,
            3u,
            expr_node,
            len))
    {
        add_func_body_len(owner_fn, len);
        publish_fragment(
            token,
            len,
            uint4(BODY_FRAGMENT_HOST_CALL_VOID, expr_node, WASM_DEALLOC_FUNC_INDEX, token),
            uint4(INVALID, 3u, 0u, 0u));
        return;
    }

    if (!print_call_node(node))
        return;

    uint kind = BODY_FRAGMENT_PRINT_I64;
    uint4 aux = uint4(INVALID, 0u, 0u, 0u);
    if (print_call_direct_call_and_len(node, expr_node, len))
    {
        kind = BODY_FRAGMENT_PRINT_DIRECT_CALL_I64;
        aux = direct_call_aux(expr_node);
    }
    else if (print_call_local_and_len(node, decl_token, len))
    {
        kind = BODY_FRAGMENT_PRINT_LOCAL_I64;
        expr_node = decl_token;
    }
    else if (print_call_value_and_len(node, value, len))
    {
        kind = BODY_FRAGMENT_PRINT_I64;
        expr_node = value;
    }
    else if (print_call_expr_and_len(node, expr_node, len))
    {
        kind = BODY_FRAGMENT_PRINT_EXPR_I64;
    }
    else
    {
        publish_func_invalid(owner_fn, token);
        return;
    }
    if (expr_mentions_local_let(call_arg0_node(node)))
        atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);

    atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
    add_func_body_len(owner_fn, len);
    atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
    publish_fragment(
        token,
        len,
        uint4(kind, expr_node, len, token),
        aux);
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
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_call(node, hir_token_pos[node]);
}
