// Validate aggregate-backed range for-loops for WASM body emission.

import atomics;
import body_common;
import body_plan_validate_common;

bool array_iterable_for_for_node(
    uint node,
    out uint binding_token,
    out uint array_local,
    out uint index_token,
    out uint array_len)
{
    binding_token = INVALID;
    array_local = INVALID;
    index_token = INVALID;
    array_len = 0u;
    if (!valid_node(node) ||
        !((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
          stmt_record_slot(node, 0u) == STMT_RECORD_KIND_FOR))
    {
        return false;
    }

    binding_token = stmt_record_slot(node, 1u);
    uint iterable_node = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_token(binding_token) ||
        !valid_node(iterable_node) ||
        expr_form(iterable_node) != HIR_EXPR_NAME)
    {
        return false;
    }

    uint name_token = expr_record_slot(iterable_node, EXPR_RECORD_VALUE_TOKEN);
    uint decl_token = valid_token(name_token) ? visible_decl[name_token] : INVALID;
    uint lit_node = valid_token(decl_token)
                        ? resolve_expr_node(body_let_init_expr_by_decl_token[decl_token])
                        : INVALID;
    if (!valid_node(lit_node) || hir_kind[lit_node] != HIR_ARRAY_EXPR)
        return false;

    uint context = hir_array_lit_context_stmt_node[lit_node];
    if (!valid_node(context) ||
        stmt_record_slot(context, 0u) != STMT_RECORD_KIND_LET ||
        stmt_record_slot(context, 1u) != decl_token ||
        !function_non_param_local_index(
            decl_token,
            node_enclosing_fn_token(node),
            array_local))
    {
        return false;
    }

    index_token = hir_token_end[iterable_node];
    array_len = hir_array_lit_element_count[lit_node];
    return valid_token(index_token);
}

bool array_for_open_fragment_and_len(
    uint node,
    out uint binding_local,
    out uint array_local,
    out uint index_local,
    out uint array_len,
    out uint len)
{
    binding_local = INVALID;
    array_local = INVALID;
    index_local = INVALID;
    array_len = 0u;
    len = 0u;
    uint binding_token = INVALID;
    uint index_token = INVALID;
    if (!array_iterable_for_for_node(
            node,
            binding_token,
            array_local,
            index_token,
            array_len) ||
        !valid_node(stmt_record_slot(node, 3u)))
    {
        return false;
    }

    uint owner_fn = node_enclosing_fn_token(node);
    if (!function_non_param_local_index(binding_token, owner_fn, binding_local) ||
        !function_non_param_local_index(index_token, owner_fn, index_local))
    {
        return false;
    }

    uint index_get_len = local_get_len(index_local);
    len = 2u + local_set_len(index_local) +
          4u +
          index_get_len + 1u + i32_sleb_len(array_len) + 3u +
          local_get_len(array_local) + index_get_len + 7u +
          local_set_len(binding_local) +
          2u;
    return true;
}

bool array_for_close_token_and_len(uint node, out uint close_token, out uint len)
{
    close_token = INVALID;
    len = 0u;
    uint binding_token = INVALID;
    uint array_local = INVALID;
    uint index_token = INVALID;
    uint array_len = 0u;
    if (!array_iterable_for_for_node(
            node,
            binding_token,
            array_local,
            index_token,
            array_len))
    {
        return false;
    }

    uint body = stmt_record_slot(node, 3u);
    uint end = valid_node(body) ? hir_token_end[body] : INVALID;
    if (end == 0u || end == INVALID)
        return false;
    close_token = end - 1u;
    uint index_local = INVALID;
    if (!valid_token(close_token) ||
        !function_non_param_local_index(
            index_token,
            node_enclosing_fn_token(node),
            index_local))
    {
        return false;
    }
    len = local_get_len(index_local) + local_set_len(index_local) + 8u;
    return true;
}

bool aggregate_range_iterable_for_for_node(
    uint node,
    out uint binding_token,
    out uint range_node,
    out uint range_local,
    out uint end_local_token)
{
    binding_token = INVALID;
    range_node = INVALID;
    range_local = INVALID;
    end_local_token = INVALID;
    if (!valid_node(node) ||
        !((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
          stmt_record_slot(node, 0u) == STMT_RECORD_KIND_FOR))
    {
        return false;
    }

    binding_token = stmt_record_slot(node, 1u);
    range_node = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_token(binding_token) || !valid_node(range_node))
        return false;
    if (expr_form(range_node) == HIR_EXPR_RANGE)
        return false;

    uint decl_token = INVALID;
    if (!aggregate_decl_for_name_expr(range_node, decl_token) ||
        wasm_agg_local_width_by_token[decl_token] != 2u)
    {
        return false;
    }
    if (!function_non_param_local_index(decl_token, node_enclosing_fn_token(node), range_local))
        return false;

    end_local_token = hir_token_end[range_node];
    return valid_token(end_local_token);
}

bool aggregate_for_open_range_fragment_and_len(
    uint node,
    out uint binding_token,
    out uint range_node,
    out uint range_local,
    out uint end_local_token,
    out uint len)
{
    binding_token = INVALID;
    range_node = INVALID;
    range_local = INVALID;
    end_local_token = INVALID;
    len = 0u;
    if (!aggregate_range_iterable_for_for_node(
            node,
            binding_token,
            range_node,
            range_local,
            end_local_token))
    {
        return false;
    }

    uint body_node = stmt_record_slot(node, 3u);
    if (!valid_node(body_node))
        return false;

    uint owner_fn = node_enclosing_fn_token(node);
    uint start_len = local_get_len(range_local) + memarg_len(0u);
    uint end_len = local_get_len(range_local) + memarg_len(4u);
    len = start_len +
          local_set_len(call_param_count[owner_fn] + binding_token) +
          end_len +
          local_set_len(call_param_count[owner_fn] + end_local_token) +
          4u +
          local_get_len(call_param_count[owner_fn] + binding_token) +
          local_get_len(call_param_count[owner_fn] + end_local_token) +
          5u;

    uint binding_local = INVALID;
    uint end_local = INVALID;
    if (!function_non_param_local_index(binding_token, owner_fn, binding_local) ||
        !function_non_param_local_index(end_local_token, owner_fn, end_local))
    {
        return false;
    }
    binding_token = binding_local;
    end_local_token = end_local;
    return true;
}

bool aggregate_for_close_token_and_len(uint node, out uint close_token, out uint len)
{
    close_token = INVALID;
    len = 0u;
    uint binding_token = INVALID;
    uint range_node = INVALID;
    uint range_local = INVALID;
    uint end_local_token = INVALID;
    if (!aggregate_range_iterable_for_for_node(
            node,
            binding_token,
            range_node,
            range_local,
            end_local_token))
    {
        return false;
    }

    uint body = stmt_record_slot(node, 3u);
    if (!valid_node(body))
        return false;

    uint end = hir_token_end[body];
    if (end == 0u || end == INVALID)
        return false;

    close_token = end - 1u;
    if (!valid_token(close_token))
        return false;

    uint binding_local = INVALID;
    if (!function_non_param_local_index(binding_token, node_enclosing_fn_token(node), binding_local))
        return false;

    len = local_get_len(binding_local) + local_set_len(binding_local) + 8u;
    return true;
}

void validate_aggregate_range_control(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (!valid_token(token) ||
        !valid_node(node) ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_FOR ||
        !((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT)))
    {
        return;
    }

    uint iterable_node = resolve_expr_node(stmt_record_slot(node, 2u));
    if (!valid_node(iterable_node) || expr_form(iterable_node) == HIR_EXPR_RANGE)
        return;

    uint array_binding_local = INVALID;
    uint array_local = INVALID;
    uint array_index_local = INVALID;
    uint array_len = 0u;
    uint array_open_len = 0u;
    uint array_close_token = INVALID;
    uint array_close_len = 0u;
    if (array_for_open_fragment_and_len(
            node,
            array_binding_local,
            array_local,
            array_index_local,
            array_len,
            array_open_len) &&
        array_for_close_token_and_len(node, array_close_token, array_close_len))
    {
        uint index_token = hir_token_end[iterable_node];
        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_local_token(owner_fn, index_token);
        add_func_body_len(owner_fn, array_open_len + array_close_len);
        publish_fragment(
            token,
            array_open_len,
            uint4(
                BODY_FRAGMENT_FOR_OPEN_ARRAY_I32,
                array_binding_local,
                array_local,
                array_index_local),
            uint4(array_len, 0u, 0u, 0u));
        publish_fragment(
            array_close_token,
            array_close_len,
            uint4(
                BODY_FRAGMENT_FOR_CLOSE_RANGE_I32,
                array_index_local,
                array_close_len,
                array_close_token),
            uint4(INVALID, 0u, 0u, 0u));
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, array_close_token);
        return;
    }

    uint binding_token = INVALID;
    uint range_node = INVALID;
    uint range_local = INVALID;
    uint end_local_token = INVALID;
    uint open_len = 0u;
    uint close_token = INVALID;
    uint close_len = 0u;
    if (!aggregate_for_open_range_fragment_and_len(
            node,
            binding_token,
            range_node,
            range_local,
            end_local_token,
            open_len) ||
        !aggregate_for_close_token_and_len(node, close_token, close_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_local_token(owner_fn, hir_token_end[range_node]);
    add_func_body_len(owner_fn, open_len + close_len);
    publish_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_FOR_OPEN_AGG_RANGE_I32, binding_token, range_local, end_local_token),
        uint4(INVALID, 0u, 0u, 0u));
    publish_fragment(
        close_token,
        close_len,
        uint4(BODY_FRAGMENT_FOR_CLOSE_RANGE_I32, binding_token, close_len, close_token),
        uint4(INVALID, 0u, 0u, 0u));
    atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, close_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;

    uint node = linear_dispatch_id(tid);
    if (node >= active_hir_node_count())
        return;

    uint token = valid_node(node) ? hir_token_pos[node] : INVALID;
    validate_aggregate_range_control(node, token);
}
