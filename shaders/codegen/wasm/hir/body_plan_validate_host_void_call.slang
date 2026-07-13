// Parallel validation and planning for statement-position host calls that
// produce no value.

import atomics;
import body_common;
import body_plan_validate_common;

void validate_main_host_void_call(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!statement_position_call(node))
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    uint callee_token = call_callee_token(node);
    uint fn_token = valid_token(callee_token)
                        ? call_fn_token_for_call(node, callee_token)
                        : INVALID;
    bool is_dealloc =
        (valid_token(callee_token) && token_has_language_name(callee_token, LANGUAGE_SYMBOL_DEALLOC)) ||
        (valid_token(fn_token) && token_has_language_name(fn_token, LANGUAGE_SYMBOL_DEALLOC));
    bool is_alloc_failed =
        (valid_token(callee_token) && token_has_language_name(callee_token, LANGUAGE_SYMBOL_ALLOC_FAILED)) ||
        (valid_token(fn_token) && token_has_language_name(fn_token, LANGUAGE_SYMBOL_ALLOC_FAILED));
    bool is_process_exit =
        (valid_token(callee_token) && token_has_language_name(callee_token, LANGUAGE_SYMBOL_EXIT)) ||
        (valid_token(fn_token) && token_has_language_name(fn_token, LANGUAGE_SYMBOL_EXIT));
    if (!is_dealloc && !is_alloc_failed && !is_process_exit)
    {
        return;
    }

    uint language_symbol = is_process_exit
                               ? LANGUAGE_SYMBOL_EXIT
                               : (is_alloc_failed ? LANGUAGE_SYMBOL_ALLOC_FAILED : LANGUAGE_SYMBOL_DEALLOC);
    uint wasm_func_index = is_process_exit
                               ? WASM_PROCESS_EXIT_FUNC_INDEX
                               : (is_alloc_failed ? WASM_ALLOC_FAILED_FUNC_INDEX : WASM_DEALLOC_FUNC_INDEX);
    uint arg_count = is_process_exit ? 1u : (is_alloc_failed ? 2u : 3u);

    uint len = 0u;
    uint expr_node = INVALID;
    if (supported_host_void_call_fragment(
            node,
            language_symbol,
            wasm_func_index,
            arg_count,
            expr_node,
            len))
    {
        add_func_body_len(owner_fn, len);
        publish_fragment(
            token,
            len,
            uint4(BODY_FRAGMENT_HOST_CALL_VOID, expr_node, wasm_func_index, token),
            uint4(INVALID, arg_count, 0u, 0u));
        publish_body_features(BODY_FEATURE_HOST | BODY_FEATURE_HOST_VOID);
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
    if (body_plan[BODY_PLAN_MAIN_COUNT] != 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_host_void_call(node, hir_token_pos[node]);
}
