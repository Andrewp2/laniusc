// Parallel validation and planning for file/std/string host-call return values.

import atomics;
import body_common;
import body_plan_validate_common;

bool return_host_io_i32_spec(uint call_node, out uint wasm_func_index, out uint arg_count)
{
    wasm_func_index = INVALID;
    arg_count = 0u;
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!valid_token(fn_token))
        return false;

    if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_READ_I32) ||
        token_has_language_name(fn_token, LANGUAGE_SYMBOL_READ_I32))
    {
        wasm_func_index = WASM_STD_READ_I32_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_I32) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_I32))
    {
        wasm_func_index = WASM_STD_WRITE_I32_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_BYTE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_BYTE))
    {
        wasm_func_index = WASM_STD_WRITE_BYTE_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_NEWLINE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_NEWLINE))
    {
        wasm_func_index = WASM_STD_WRITE_NEWLINE_FUNC_INDEX;
        arg_count = 1u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_CLOSE_FILE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_CLOSE_FILE) ||
             token_has_language_name(callee_token, LANGUAGE_SYMBOL_CLOSE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_CLOSE))
    {
        wasm_func_index = WASM_FS_CLOSE_FUNC_INDEX;
        arg_count = 1u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_READ) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_READ))
    {
        wasm_func_index = WASM_FS_READ_FUNC_INDEX;
        arg_count = 3u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE))
    {
        wasm_func_index = WASM_FS_WRITE_FUNC_INDEX;
        arg_count = 3u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_OPEN_READ) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_OPEN_READ))
    {
        wasm_func_index = WASM_FS_OPEN_READ_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_OPEN_WRITE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_OPEN_WRITE))
    {
        wasm_func_index = WASM_FS_OPEN_WRITE_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_OPEN_APPEND) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_OPEN_APPEND))
    {
        wasm_func_index = WASM_FS_OPEN_APPEND_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_STDERR) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_STDERR))
    {
        wasm_func_index = WASM_STDIO_WRITE_STDERR_FUNC_INDEX;
        arg_count = 2u;
    }
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_READ_STDIN) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_READ_STDIN))
    {
        wasm_func_index = WASM_STDIO_READ_STDIN_FUNC_INDEX;
        arg_count = 2u;
    }
    else
    {
        return false;
    }

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    if (!host_i32_abi_return_type(return_ty) || hir_call_arg_count[call_node] != arg_count)
        return false;

    for (uint i = 0u; i < arg_count; i += 1u)
    {
        if (!host_i32_abi_param_type(call_param_type_value(fn_token, i)))
            return false;
    }
    return true;
}

bool return_host_io_i32_call_len(uint call_node, uint wasm_func_index, uint arg_count, out uint len)
{
    len = 1u + u32_leb_len(wasm_func_index);
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_len = 0u;
        if (!direct_call_arg_scalar_and_len(direct_call_arg_node(call_node, i), arg_len))
            return false;
        len += arg_len;
    }
    return true;
}

bool supported_return_host_io_i32_fragment(
    uint node,
    out uint call_node,
    out uint wasm_func_index,
    out uint arg_count,
    out uint len)
{
    call_node = INVALID;
    wasm_func_index = INVALID;
    arg_count = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_RETURN_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    call_node = resolve_expr_node(stmt_record_slot(node, 1u));
    if (!return_host_io_i32_spec(call_node, wasm_func_index, arg_count) ||
        !return_host_io_i32_call_len(call_node, wasm_func_index, arg_count, len))
    {
        return false;
    }
    len += 1u;
    return true;
}

bool supported_return_host_string_fragment(
    uint node,
    out uint call_node,
    out uint wasm_func_index,
    out uint mode,
    out uint len)
{
    call_node = INVALID;
    wasm_func_index = INVALID;
    mode = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_RETURN_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    call_node = resolve_expr_node(stmt_record_slot(node, 1u));
    if (host_string_i32_call_expr_and_len(
            call_node,
            LANGUAGE_SYMBOL_OPEN_READ_PATH,
            WASM_STD_OPEN_READ_PATH_FUNC_INDEX,
            HOST_STR_CALL_OPEN_READ_PATH,
            len))
    {
        wasm_func_index = WASM_STD_OPEN_READ_PATH_FUNC_INDEX;
        mode = HOST_STR_CALL_OPEN_READ_PATH;
    }
    else if (host_string_i32_call_expr_and_len(
                 call_node,
                 LANGUAGE_SYMBOL_OPEN_WRITE_PATH,
                 WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX,
                 HOST_STR_CALL_OPEN_WRITE_PATH,
                 len))
    {
        wasm_func_index = WASM_STD_OPEN_WRITE_PATH_FUNC_INDEX;
        mode = HOST_STR_CALL_OPEN_WRITE_PATH;
    }
    else if (host_string_i32_call_expr_and_len(
                 call_node,
                 LANGUAGE_SYMBOL_WRITE_TEXT,
                 WASM_STD_WRITE_TEXT_FUNC_INDEX,
                 HOST_STR_CALL_WRITE_TEXT,
                 len))
    {
        wasm_func_index = WASM_STD_WRITE_TEXT_FUNC_INDEX;
        mode = HOST_STR_CALL_WRITE_TEXT;
    }
    else
    {
        return false;
    }

    len += 1u;
    return true;
}

void validate_main_return_host_io(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_RETURN_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return;
    }

    uint expr = resolve_expr_node(stmt_record_slot(node, 1u));
    if (!valid_node(expr) || hir_kind[expr] != HIR_CALL_EXPR)
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u)
        return;

    uint expr_node = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    uint mode = 0u;
    uint len = 0u;
    uint kind = BODY_FRAGMENT_RETURN_HOST_CALL_I32;
    uint4 aux = uint4(INVALID, 0u, 0u, 0u);
    if (supported_return_host_io_i32_fragment(
            node,
            expr_node,
            wasm_func_index,
            arg_count,
            len))
    {
        aux = uint4(INVALID, arg_count, 0u, 0u);
    }
    else if (supported_return_host_string_fragment(
            node,
            expr_node,
            wasm_func_index,
            mode,
            len))
    {
        kind = BODY_FRAGMENT_RETURN_HOST_STR_CALL_I32;
        aux = uint4(INVALID, 0u, mode, 0u);
    }
    else
    {
        return;
    }

    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
    add_func_body_len(owner_fn, len);
    publish_fragment(token, len, uint4(kind, expr_node, wasm_func_index, token), aux);
    publish_body_features(BODY_FEATURE_HOST | BODY_FEATURE_HOST_IO);
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
    if (!valid_node(node) || hir_kind[node] != HIR_RETURN_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_return_host_io(node, hir_token_pos[node]);
}
