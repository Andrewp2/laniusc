// Parallel validation and planning for fixed host-call let initializers.

import atomics;
import body_common;
import body_plan_validate_common;

void publish_let_host_call(uint node, uint token, uint owner_fn, uint len, uint4 meta, uint4 aux)
{
    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_body_len(owner_fn, len);
    publish_fragment(token, len, meta, aux);
}

void publish_let_basic_host_call(uint node, uint token, uint owner_fn, uint len, uint4 meta, uint4 aux)
{
    publish_let_host_call(node, token, owner_fn, len, meta, aux);
    publish_body_features(
        BODY_FEATURE_HOST |
        BODY_FEATURE_HOST_BASIC |
        BODY_FEATURE_MEMBER_EXPR_SCATTER);
}

void validate_main_let_host(uint node, uint token)
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
    if (supported_let_i32_array_data_ptr_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_I32_ARRAY_DATA_PTR, decl_token, expr_node, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (supported_let_host_stdout_write_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_HOST_STDOUT_WRITE_I32, decl_token, expr_node, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (supported_let_host_process_argc_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_HOST_NO_ARG_I32, decl_token, expr_node, WASM_PROCESS_ARGC_FUNC_INDEX),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (supported_let_host_process_arg_len_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_PROCESS_ARG_LEN_I32, decl_token, expr_node, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (supported_let_host_process_arg_read_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_PROCESS_ARG_READ_I32, decl_token, expr_node, token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (supported_let_host_secure_u32_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_HOST_NO_ARG_I32, decl_token, expr_node, WASM_RANDOM_SECURE_U32_FUNC_INDEX),
            uint4(INVALID, 0u, 0u, 0u));
    }
    else if (supported_let_host_unix_seconds_fragment(node, decl_token, expr_node, len))
    {
        publish_let_basic_host_call(
            node,
            token,
            owner_fn,
            len,
            uint4(BODY_FRAGMENT_LET_HOST_NO_ARG_I32, decl_token, expr_node, WASM_TIME_UNIX_SECONDS_FUNC_INDEX),
            uint4(INVALID, 0u, 0u, 0u));
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
    validate_main_let_host(node, hir_token_pos[node]);
}
