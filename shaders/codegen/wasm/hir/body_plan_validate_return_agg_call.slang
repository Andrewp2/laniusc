// Parallel validation and planning for aggregate-return WASM direct calls.

import atomics;
import body_common;
import body_plan_validate_common;
import call_relocation;

bool aggregate_direct_call_info(
    uint node,
    out uint tail_len,
    out uint fn_token,
    out uint wasm_func_index,
    out uint arg_count,
    out uint detail)
{
    tail_len = 0u;
    fn_token = INVALID;
    wasm_func_index = INVALID;
    arg_count = 0u;
    detail = INVALID;

    node = resolve_expr_node(node);
    detail = valid_node(node) ? hir_token_pos[node] : INVALID;
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(node);
    if (valid_token(callee_token))
        detail = callee_token;
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    fn_token = call_fn_token_for_call(node, callee_token);
    if (valid_token(fn_token))
        detail = fn_token;
    if (!supported_call_target_token(fn_token))
        return false;

    uint return_ty = call_return_type_for_call(node, callee_token, fn_token);
    if (return_ty < TY_ARRAY_BASE)
        return false;

    bool has_receiver_arg = direct_call_has_receiver_arg(node, fn_token);
    arg_count = hir_call_arg_count[node] + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    wasm_func_index = wasm_call_target_for_call(node, fn_token);
    tail_len = 1u + wasm_call_index_len(wasm_func_index);
    detail = INVALID;
    return true;
}

void validate_main_return_agg_call(uint node, uint token)
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
    if (body_fragment_len[token * 2u] != 0u)
        return;

    uint call_node = resolve_expr_node(stmt_record_slot(node, 1u));
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint call_tail_len = 0u;
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    uint detail = token;
    if (!aggregate_direct_call_info(
            call_node,
            call_tail_len,
            fn_token,
            wasm_func_index,
            arg_count,
            detail))
    {
        return;
    }

    uint len = call_tail_len + 1u;
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_RETURN_AGG_DIRECT);
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32, call_node, len, token),
        uint4(wasm_func_index, arg_count, fn_token, 0u));
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
    if (!valid_node(node) || hir_kind[node] != HIR_RETURN_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_return_agg_call(node, hir_token_pos[node]);
}
