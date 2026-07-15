// Parallel validation and planning for allocation/environment host let calls.

import atomics;
import body_common;
import body_plan_validate_common;

void publish_env_let_call(
    uint node,
    uint token,
    uint owner_fn,
    uint len,
    uint local_index,
    uint call_node,
    uint wasm_func_index,
    uint arg_count)
{
    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_LET_HOST_CALL_I32, local_index, call_node, wasm_func_index),
        uint4(INVALID, arg_count, 0u, 0u));
    publish_body_features(
        BODY_FEATURE_HOST |
        BODY_FEATURE_HOST_ENV |
        BODY_FEATURE_MEMBER_EXPR_SCATTER);
}

void validate_main_let_host_env(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_node(init_expr) || hir_kind[init_expr] != HIR_CALL_EXPR)
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u)
        return;

    uint decl_token = INVALID;
    uint expr_node = INVALID;
    uint len = 0u;
    if (supported_let_host_i32_call_fragment(
            node,
            LANGUAGE_SYMBOL_ALLOC,
            WASM_ALLOC_FUNC_INDEX,
            2u,
            decl_token,
            expr_node,
            len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ALLOC_FUNC_INDEX, 2u);
    }
    else if (supported_let_host_i32_call_fragment(
                 node,
                 LANGUAGE_SYMBOL_CURRENT_DIR_READ,
                 WASM_ENV_CURRENT_DIR_READ_FUNC_INDEX,
                 2u,
                 decl_token,
                 expr_node,
                 len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ENV_CURRENT_DIR_READ_FUNC_INDEX, 2u);
    }
    else if (supported_let_host_i32_call_fragment(
                 node,
                 LANGUAGE_SYMBOL_VAR_COUNT,
                 WASM_ENV_VAR_COUNT_FUNC_INDEX,
                 0u,
                 decl_token,
                 expr_node,
                 len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ENV_VAR_COUNT_FUNC_INDEX, 0u);
    }
    else if (supported_let_host_i32_call_fragment(
                 node,
                 LANGUAGE_SYMBOL_VAR_KEY_LEN,
                 WASM_ENV_VAR_KEY_LEN_FUNC_INDEX,
                 1u,
                 decl_token,
                 expr_node,
                 len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ENV_VAR_KEY_LEN_FUNC_INDEX, 1u);
    }
    else if (supported_let_host_i32_call_fragment(
                 node,
                 LANGUAGE_SYMBOL_VAR_KEY_READ,
                 WASM_ENV_VAR_KEY_READ_FUNC_INDEX,
                 3u,
                 decl_token,
                 expr_node,
                 len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ENV_VAR_KEY_READ_FUNC_INDEX, 3u);
    }
    else if (supported_let_host_i32_call_fragment(
                 node,
                 LANGUAGE_SYMBOL_VAR_LEN,
                 WASM_ENV_VAR_LEN_FUNC_INDEX,
                 2u,
                 decl_token,
                 expr_node,
                 len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ENV_VAR_LEN_FUNC_INDEX, 2u);
    }
    else if (supported_let_host_i32_call_fragment(
                 node,
                 LANGUAGE_SYMBOL_VAR_READ,
                 WASM_ENV_VAR_READ_FUNC_INDEX,
                 4u,
                 decl_token,
                 expr_node,
                 len))
    {
        publish_env_let_call(node, token, owner_fn, len, decl_token, expr_node, WASM_ENV_VAR_READ_FUNC_INDEX, 4u);
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
    if (!valid_node(node) || hir_kind[node] != HIR_LET_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_let_host_env(node, hir_token_pos[node]);
}
