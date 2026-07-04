// Plan aggregate struct literal allocation and field-store fragments.

import atomics;
import body_common;
import body_plan_validate_common;

StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;

bool aggregate_lit_let_decl(uint lit_node, out uint let_node, out uint decl_token)
{
    let_node = INVALID;
    decl_token = INVALID;
    if (!valid_node(lit_node) || hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
        return false;

    uint current = hir_struct_lit_context_stmt_node[lit_node];
    if (valid_node(current) &&
        hir_kind[current] == HIR_LET_STMT &&
        stmt_record_slot(current, 0u) == STMT_RECORD_KIND_LET)
    {
        decl_token = stmt_record_slot(current, 1u);
        let_node = current;
        return valid_token(decl_token);
    }
    return false;
}

bool aggregate_lit_return_token(uint lit_node, out uint return_node, out uint return_token)
{
    return_node = INVALID;
    return_token = INVALID;
    if (!valid_node(lit_node) || hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
        return false;

    uint current = hir_struct_lit_context_stmt_node[lit_node];
    if (valid_node(current) &&
        hir_kind[current] == HIR_RETURN_STMT &&
        stmt_record_slot(current, 0u) == STMT_RECORD_KIND_RETURN)
    {
        return_token = hir_token_pos[current];
        return_node = current;
        return valid_token(return_token);
    }
    return false;
}

void account_let_struct_literal(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_STRUCT_LITERAL_EXPR)
        return;

    uint let_node = INVALID;
    uint decl_token = INVALID;
    if (!aggregate_lit_let_decl(node, let_node, decl_token))
        return;

    if (!valid_token(decl_token) || wasm_agg_local_width_by_token[decl_token] == 0u)
        return;

    uint local_index = INVALID;
    if (!function_non_param_local_index(decl_token, owner_fn, local_index))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint len = 1u + i32_sleb_len(base_address) + local_set_len(local_index);
    uint let_token = hir_token_pos[let_node];
    if (!valid_token(let_token))
        let_token = token;
    add_func_local_token(owner_fn, decl_token);
    add_func_body_len(owner_fn, len);
    publish_fragment_slot(
        let_token * 2u + 1u,
        len,
        uint4(BODY_FRAGMENT_LET_ARRAY_I32, local_index, base_address, let_token),
        uint4(0u, 0u, 0u, 0u));
}

void account_return_struct_literal(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_STRUCT_LITERAL_EXPR)
        return;

    uint return_node = INVALID;
    uint return_token = INVALID;
    if (!aggregate_lit_return_token(node, return_node, return_token))
        return;

    if (!valid_token(return_token) || wasm_agg_local_width_by_token[return_token] == 0u)
        return;

    uint base_address = aggregate_data_base() + agg_local_base_slots(return_token) * 4u;
    uint len = 1u + i32_sleb_len(base_address) + 1u;
    uint return_slot_token = return_token;
    uint lit_end = hir_token_end[node];
    if (valid_token_end(lit_end) && lit_end > 0u)
        return_slot_token = lit_end - 1u;
    publish_return_value(base_address);
    add_func_body_len(owner_fn, len);
    publish_fragment_slot(
        return_slot_token * 2u + 1u,
        len,
        uint4(BODY_FRAGMENT_RETURN_I32, base_address, len, return_token),
        uint4(0u, 0u, 0u, 0u));
}

void account_struct_field_store(uint node, uint owner_fn, uint token)
{
    if (hir_kind[node] != HIR_NONE)
        return;

    uint lit_node = hir_struct_lit_field_parent_lit[node];
    if (!valid_node(lit_node))
        return;
    if (lit_node == node)
        return;
    if (hir_kind[lit_node] != HIR_STRUCT_LITERAL_EXPR)
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint let_node = INVALID;
    uint decl_token = INVALID;
    uint return_node = INVALID;
    uint return_token = INVALID;
    bool has_let_target = aggregate_lit_let_decl(lit_node, let_node, decl_token);
    bool has_return_target = aggregate_lit_return_token(lit_node, return_node, return_token);
    if (!has_let_target && !has_return_target)
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint field_index = struct_init_field_ordinal_by_node[node];
    uint value_node = hir_struct_lit_field_value_node[node];
    uint expr_len = 0u;
    if (field_index == INVALID ||
        !valid_node(value_node) ||
        !expr_simple_and_len(value_node, expr_len))
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint storage_token = has_let_target ? decl_token : return_token;
    uint address = aggregate_data_base() + (agg_local_base_slots(storage_token) + field_index) * 4u;
    uint len = 1u + i32_sleb_len(address) + expr_len + 3u;
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_AGG_FIELD_STORE_I32, address, value_node, token),
        uint4(0u, 0u, 0u, 0u));
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
    if (!valid_node(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;

    uint token = hir_token_pos[node];
    account_let_struct_literal(node, owner_fn, token);
    account_return_struct_literal(node, owner_fn, token);
    account_struct_field_store(node, owner_fn, token);
}
