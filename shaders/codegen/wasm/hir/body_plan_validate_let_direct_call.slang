// Parallel validation and planning for plain scalar WASM direct-call let initializers.

import atomics;
import body_common;
import body_plan_validate_common;

bool direct_call_header_aux(uint call_node, out uint4 aux)
{
    aux = uint4(INVALID, 0u, INVALID, 0u);
    call_node = resolve_expr_node(call_node);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(call_node, callee_token);
    if (!supported_function_token(fn_token))
        return false;

    uint explicit_arg_count = hir_call_arg_count[call_node];
    bool has_receiver_arg = direct_call_has_receiver_arg(call_node, fn_token);
    uint arg_count = explicit_arg_count + (has_receiver_arg ? 1u : 0u);
    if (call_param_count[fn_token] != arg_count)
        return false;

    uint return_ty = call_return_type_for_call(call_node, callee_token, fn_token);
    if (!type_is_i32_value(return_ty) && return_ty != TY_FLOAT)
        return false;

    uint wasm_func_index = wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT;
    aux = uint4(wasm_func_index, arg_count, fn_token, 0u);
    return true;
}

void validate_main_let_direct_call(uint node, uint token)
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
    uint4 aux = uint4(INVALID, 0u, INVALID, 0u);
    if (!direct_call_header_aux(init_expr, aux))
        return;

    decl_token = stmt_record_slot(node, 1u);
    uint local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;
    uint local_index = INVALID;
    if (!valid_token(decl_token) ||
        !function_non_param_local_index_for_type(
            decl_token,
            owner_fn,
            local_ty,
            local_index))
    {
        return;
    }

    expr_node = init_expr;
    uint len = 1u + u32_leb_len(aux.x) + local_set_len(local_index);
    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_LET_DIRECT_CALL_I32, local_index, expr_node, token),
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
    if (!valid_node(node) || hir_kind[node] != HIR_LET_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_let_direct_call(node, hir_token_pos[node]);
}
