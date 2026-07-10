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
    if ((!valid_token(callee_token) ||
         !token_has_language_name(callee_token, LANGUAGE_SYMBOL_DEALLOC)) &&
        (!valid_token(fn_token) ||
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_DEALLOC)))
    {
        return;
    }

    uint len = 0u;
    uint expr_node = INVALID;
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
