// Parallel validation and planning for file/string host-call let initializers.

import atomics;
import body_common;
import body_plan_validate_common;

void validate_main_let_host_io(uint node, uint token)
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
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    uint mode = 0u;
    uint len = 0u;
    uint kind = BODY_FRAGMENT_LET_HOST_CALL_I32;
    uint4 aux = uint4(INVALID, 0u, 0u, 0u);
    if (supported_let_file_stdio_host_i32_call_fragment(
            node,
            decl_token,
            expr_node,
            wasm_func_index,
            arg_count,
            len))
    {
        aux = uint4(INVALID, arg_count, 0u, 0u);
    }
    else if (supported_let_host_string_call_fragment(
            node,
            decl_token,
            expr_node,
            wasm_func_index,
            mode,
            len))
    {
        kind = BODY_FRAGMENT_LET_HOST_STR_CALL_I32;
        aux = uint4(INVALID, mode, 0u, 0u);
    }
    else
    {
        return;
    }

    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_body_len(owner_fn, len);
    publish_fragment(token, len, uint4(kind, decl_token, expr_node, wasm_func_index), aux);
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
    if (!valid_node(node) || hir_kind[node] != HIR_LET_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_let_host_io(node, hir_token_pos[node]);
}
