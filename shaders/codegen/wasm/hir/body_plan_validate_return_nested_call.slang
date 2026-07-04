// Parallel validation and planning for WASM return direct calls with one nested direct-call argument.

import atomics;
import body_common;
import body_plan_validate_common;

bool return_nested_direct_call_arg_and_len(
    uint node,
    out uint len,
    out uint nested_wasm_func_index,
    out uint nested_arg_count,
    out uint nested_fn_token)
{
    len = 0u;
    nested_wasm_func_index = INVALID;
    nested_arg_count = 0u;
    nested_fn_token = INVALID;
    node = resolve_expr_node(node);
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    if (!direct_user_call_node(node, fn_token, wasm_func_index, arg_count))
        return false;

    uint total = 1u + u32_leb_len(wasm_func_index);
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_abi_arg_node(node, fn_token, i);
        uint arg_len = 0u;
        if (!direct_call_arg_expr_and_len(arg_node, arg_len) || arg_len == 0u)
            return false;
        total += arg_len;
    }

    len = total;
    nested_wasm_func_index = wasm_func_index;
    nested_arg_count = arg_count;
    nested_fn_token = fn_token;
    return true;
}

bool return_direct_call_expr_and_len(
    uint node,
    out uint len,
    out uint nested_arg_ordinal,
    out uint nested_wasm_func_index,
    out uint nested_arg_count,
    out uint nested_fn_token)
{
    len = 0u;
    nested_arg_ordinal = INVALID;
    nested_wasm_func_index = INVALID;
    nested_arg_count = 0u;
    nested_fn_token = INVALID;
    node = resolve_expr_node(node);
    uint fn_token = INVALID;
    uint wasm_func_index = INVALID;
    uint arg_count = 0u;
    if (!direct_user_call_node(node, fn_token, wasm_func_index, arg_count))
        return false;

    uint total = 1u + u32_leb_len(wasm_func_index);
    bool nested = false;
    for (uint i = 0u; i < arg_count; i += 1u)
    {
        uint arg_node = direct_call_abi_arg_node(node, fn_token, i);
        uint arg_len = 0u;
        bool ok = direct_call_arg_expr_and_len(arg_node, arg_len);
        if (!ok)
        {
            uint candidate_wasm_func_index = INVALID;
            uint candidate_arg_count = 0u;
            uint candidate_fn_token = INVALID;
            ok = return_nested_direct_call_arg_and_len(
                arg_node,
                arg_len,
                candidate_wasm_func_index,
                candidate_arg_count,
                candidate_fn_token);
            nested = ok;
            if (ok)
            {
                nested_arg_ordinal = i;
                nested_wasm_func_index = candidate_wasm_func_index;
                nested_arg_count = candidate_arg_count;
                nested_fn_token = candidate_fn_token;
            }
        }
        if (!ok || arg_len == 0u)
            return false;
        total += arg_len;
    }

    len = total;
    return true;
}

bool return_direct_call_fragment_and_len(
    uint stmt_node,
    out uint expr_node,
    out uint len,
    out bool nested,
    out uint nested_arg_ordinal,
    out uint nested_wasm_func_index,
    out uint nested_arg_count,
    out uint nested_fn_token)
{
    expr_node = INVALID;
    len = 0u;
    nested = false;
    nested_arg_ordinal = INVALID;
    nested_wasm_func_index = INVALID;
    nested_arg_count = 0u;
    nested_fn_token = INVALID;
    if (!valid_node(stmt_node) ||
        hir_kind[stmt_node] != HIR_RETURN_STMT ||
        stmt_record_slot(stmt_node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    expr_node = resolve_expr_node(stmt_record_slot(stmt_node, 1u));
    uint expr_len = 0u;
    if (!valid_node(expr_node) ||
        !return_direct_call_expr_and_len(
            expr_node,
            expr_len,
            nested_arg_ordinal,
            nested_wasm_func_index,
            nested_arg_count,
            nested_fn_token))
    {
        return false;
    }

    len = expr_len + 1u;
    nested = nested_arg_ordinal != INVALID;
    return true;
}

bool return_call_candidate(uint stmt_node)
{
    if (!valid_node(stmt_node) ||
        hir_kind[stmt_node] != HIR_RETURN_STMT ||
        stmt_record_slot(stmt_node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    uint expr_node = resolve_expr_node(stmt_record_slot(stmt_node, 1u));
    if (!valid_node(expr_node))
        return false;
    return hir_kind[expr_node] == HIR_CALL_EXPR;
}

bool return_aggregate_direct_call_candidate(uint stmt_node)
{
    if (!valid_node(stmt_node) ||
        hir_kind[stmt_node] != HIR_RETURN_STMT ||
        stmt_record_slot(stmt_node, 0u) != STMT_RECORD_KIND_RETURN)
    {
        return false;
    }

    uint expr_node = resolve_expr_node(stmt_record_slot(stmt_node, 1u));
    if (!valid_node(expr_node) || hir_kind[expr_node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(expr_node);
    if (!valid_token(callee_token) || call_intrinsic_tag[callee_token] != 0u)
        return false;

    uint fn_token = call_fn_token_for_call(expr_node, callee_token);
    if (!supported_function_token(fn_token))
        return false;

    return call_return_type_for_call(expr_node, callee_token, fn_token) >= TY_ARRAY_BASE;
}

void validate_main_return_call(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_RETURN_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_RETURN ||
        body_fragment_len[token * 2u] != 0u)
    {
        return;
    }

    uint return_expr_node = INVALID;
    uint return_len = 0u;
    bool nested = false;
    uint nested_arg_ordinal = INVALID;
    uint nested_wasm_func_index = INVALID;
    uint nested_arg_count = 0u;
    uint nested_fn_token = INVALID;
    if (!return_direct_call_fragment_and_len(
            node,
            return_expr_node,
            return_len,
            nested,
            nested_arg_ordinal,
            nested_wasm_func_index,
            nested_arg_count,
            nested_fn_token))
    {
        if (return_aggregate_direct_call_candidate(node))
            return;
        if (return_call_candidate(node))
        {
            atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_INVALID_COUNT, 1u);
            publish_func_invalid(owner_fn, token);
        }
        return;
    }

    uint4 aux = direct_call_aux(return_expr_node);
    if (nested)
    {
        aux.w = nested_arg_ordinal + 1u;
        atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_RETURN_NESTED_DIRECT);
    }
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
    add_func_body_len(owner_fn, return_len);
    publish_fragment(
        token,
        return_len,
        uint4(
            BODY_FRAGMENT_RETURN_DIRECT_CALL_I32,
            return_expr_node,
            nested ? nested_wasm_func_index : return_len,
            nested ? nested_fn_token : token),
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
    if (!valid_node(node) || hir_kind[node] != HIR_RETURN_STMT)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_return_call(node, hir_token_pos[node]);
}
