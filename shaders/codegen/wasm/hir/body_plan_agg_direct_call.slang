// Plan aggregate let-initializer direct-call body fragments.

import atomics;
import body_common;
import body_plan_validate_common;
import call_relocation;

bool aggregate_direct_call_info(
    uint node,
    bool expected_aggregate_return,
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
    bool unknown_return = return_ty == TY_UNKNOWN || return_ty == INVALID;
    if (return_ty < TY_ARRAY_BASE && !(expected_aggregate_return && unknown_return))
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

bool aggregate_let_call_context(
    uint call_node,
    out uint let_node,
    out uint decl_token,
    out uint token)
{
    let_node = INVALID;
    decl_token = INVALID;
    token = INVALID;

    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    let_node = hir_call_context_stmt_node[call_node];
    if (!valid_node(let_node) || stmt_record_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
        return false;

    decl_token = stmt_record_slot(let_node, 1u);
    uint init_expr = valid_token(decl_token) ? body_let_init_expr_by_decl_token[decl_token] : INVALID;
    if (!valid_node(init_expr))
        init_expr = stmt_record_slot(let_node, 2u);
    if (resolve_expr_node(init_expr) != resolve_expr_node(call_node))
        return false;

    token = hir_token_pos[let_node];
    if (!valid_token(token))
        token = hir_token_pos[call_node];
    return valid_token(token);
}

void account_let_aggregate_direct_call(uint call_node, uint decl_token, uint owner_fn, uint token)
{
    if (!valid_token(decl_token) ||
        (visible_type_for_token(decl_token) < TY_ARRAY_BASE &&
         wasm_agg_local_width_by_token[decl_token] == 0u))
    {
        return;
    }

    uint call_tail_len = 0u;
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    uint detail = token;
    if (!aggregate_direct_call_info(
            call_node,
            wasm_agg_local_width_by_token[decl_token] != 0u,
            call_tail_len,
            fn_token,
            wasm_func_index,
            arg_count,
            detail))
    {
        publish_func_invalid(owner_fn, valid_token(detail) ? detail : token);
        return;
    }

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint width = wasm_agg_local_width_by_token[decl_token];
    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint copy_len =
        (1u + i32_sleb_len(base_address)) +
        local_get_len(local_index) +
        (1u + i32_sleb_len(width * 4u)) +
        4u +
        (1u + i32_sleb_len(base_address)) +
        local_set_len(local_index);
    uint call_set_tail_len = call_tail_len + local_set_len(local_index);
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, call_set_tail_len + copy_len);
    publish_fragment_slot(
        token * 2u,
        call_set_tail_len,
        uint4(BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32, local_index, call_node, token),
        uint4(wasm_func_index, arg_count, fn_token, 0u));
    publish_fragment_slot(
        token * 2u + 1u,
        copy_len,
        uint4(BODY_FRAGMENT_AGG_DIRECT_COPY_I32, local_index, decl_token, token),
        uint4(0u, 0u, 0u, 0u));
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
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint let_node = INVALID;
    uint decl_token = INVALID;
    uint token = INVALID;
    if (!aggregate_let_call_context(node, let_node, decl_token, token))
        return;

    uint owner_fn = node_enclosing_fn_token(let_node);
    if (!supported_function_token(owner_fn))
        return;
    account_let_aggregate_direct_call(node, decl_token, owner_fn, token);
}
