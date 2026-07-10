// Parallel validation and planning for string-backed file/std host-call let
// initializers.

import atomics;
import body_common;
import body_plan_validate_common;

bool host_string_call_candidate(uint call_node)
{
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    return token_has_language_name(callee_token, LANGUAGE_SYMBOL_OPEN_READ_PATH) ||
           token_has_language_name(fn_token, LANGUAGE_SYMBOL_OPEN_READ_PATH) ||
           token_has_language_name(callee_token, LANGUAGE_SYMBOL_OPEN_WRITE_PATH) ||
           token_has_language_name(fn_token, LANGUAGE_SYMBOL_OPEN_WRITE_PATH) ||
           token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_TEXT) ||
           token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_TEXT);
}

void validate_main_let_host_string(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_node(init_expr) ||
        hir_kind[init_expr] != HIR_CALL_EXPR ||
        !host_string_call_candidate(init_expr))
    {
        return;
    }

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }
    if (body_fragment_len[token * 2u] != 0u)
        return;

    uint local_index = INVALID;
    uint call_node = INVALID;
    uint wasm_func_index = INVALID;
    uint mode = 0u;
    uint len = 0u;
    if (!supported_let_host_string_call_fragment(
            node,
            local_index,
            call_node,
            wasm_func_index,
            mode,
            len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(
            BODY_FRAGMENT_LET_HOST_STR_CALL_I32,
            local_index,
            call_node,
            wasm_func_index),
        uint4(INVALID, mode, 0u, 0u));
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
    if (!valid_node(node) || hir_kind[node] != HIR_LET_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_let_host_string(node, hir_token_pos[node]);
}
