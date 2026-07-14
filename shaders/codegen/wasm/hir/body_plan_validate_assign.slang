// Parallel validation and aggregate planning for scalar WASM assignments.

import atomics;
import body_common;
import body_plan_validate_common;

bool member_assign_rhs_and_len(uint node, out uint len)
{
    len = 0u;
    if (expr_non_call_atom_and_len(node, len))
        return true;

    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    uint left_len = 0u;
    uint right_len = 0u;
    if (!expr_binary_op_supported(form) ||
        expr_binary_op_byte_for_node(node) == 0u ||
        !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_LEFT), left_len) ||
        !expr_non_call_atom_and_len(expr_record_slot(node, EXPR_RECORD_RIGHT), right_len))
    {
        return false;
    }
    len = left_len + right_len + 1u;
    return true;
}

bool supported_assign_member_expr_fragment(
    uint node,
    out uint target_member,
    out uint rhs_node,
    out uint op,
    out uint len)
{
    target_member = INVALID;
    rhs_node = INVALID;
    op = 0u;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return false;
    }

    target_member = resolve_expr_node(stmt_record_slot(node, 1u));
    rhs_node = stmt_record_slot(node, 2u);
    op = stmt_record_slot(node, 3u);
    if (!valid_node(target_member) ||
        hir_kind[target_member] != HIR_MEMBER_EXPR ||
        !assign_op_supported(op))
    {
        return false;
    }

    uint member_name = hir_member_name_token[target_member];
    uint field_index = valid_token(member_name)
                           ? member_result_field_index[member_name]
                           : INVALID;
    uint field_ty = valid_token(member_name)
                        ? visible_type_for_token(member_name)
                        : TY_UNKNOWN;
    uint address_len = 0u;
    uint rhs_len = 0u;
    if (field_index == INVALID ||
        field_ty >= TY_ARRAY_BASE ||
        !aggregate_address_expr_and_len(
            hir_member_receiver_node[target_member],
            address_len) ||
        !member_assign_rhs_and_len(rhs_node, rhs_len))
    {
        return false;
    }

    uint access_len = memarg_len(field_index * 4u);
    len = op == ASSIGN_OP_SET
              ? address_len + rhs_len + access_len
              : address_len * 2u + access_len + rhs_len + 1u + access_len;
    return true;
}

void validate_main_assign(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] != HIR_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_ASSIGN)
    {
        return;
    }

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    uint member_target = INVALID;
    uint member_rhs = INVALID;
    uint member_op = 0u;
    uint member_len = 0u;
    if (supported_assign_member_expr_fragment(
            node,
            member_target,
            member_rhs,
            member_op,
            member_len))
    {
        uint kind = member_op == ASSIGN_OP_SET
                        ? BODY_FRAGMENT_ASSIGN_MEMBER_EXPR_I32
                        : BODY_FRAGMENT_ASSIGN_MEMBER_COMPOUND_EXPR_I32;
        add_func_body_len(owner_fn, member_len);
        publish_fragment(
            token,
            member_len,
            uint4(kind, member_target, member_rhs, member_op),
            uint4(INVALID, 0u, 0u, 0u));
        publish_body_features(BODY_FEATURE_AGG_COPY);
        return;
    }

    uint raw_rhs_node = resolve_expr_node(stmt_record_slot(node, 2u));
    if (valid_node(raw_rhs_node) && expr_form(raw_rhs_node) == HIR_EXPR_INDEX)
        return;

    uint target_decl = INVALID;
    uint rhs_node = INVALID;
    uint rhs_value = 0u;
    uint op = 0u;
    uint len = 0u;
    uint kind = op == ASSIGN_OP_SET
                    ? BODY_FRAGMENT_ASSIGN_CONST_I32
                    : BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32;
    uint value = rhs_value;
    uint4 aux = uint4(INVALID, 0u, 0u, 0u);
    bool runtime_expr = true;
    if (supported_assign_direct_call_fragment(node, target_decl, rhs_node, op, len))
    {
        kind = op == ASSIGN_OP_SET
                   ? BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32
                   : BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32;
        value = rhs_node;
        aux = direct_call_aux(rhs_node);
    }
    else if (supported_assign_const_fragment(node, target_decl, rhs_value, op, len))
    {
        runtime_expr = false;
        kind = op == ASSIGN_OP_SET
                   ? BODY_FRAGMENT_ASSIGN_CONST_I32
                   : BODY_FRAGMENT_ASSIGN_COMPOUND_CONST_I32;
        value = rhs_value;
    }
    else if (supported_assign_expr_fragment(node, target_decl, rhs_node, op, len))
    {
        kind = op == ASSIGN_OP_SET
                   ? BODY_FRAGMENT_ASSIGN_EXPR_I32
                   : BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_I32;
        value = rhs_node;
        publish_body_features(BODY_FEATURE_MEMBER_EXPR_SCATTER);
    }
    else
    {
        publish_func_invalid(owner_fn, token);
        return;
    }

    uint rhs = stmt_record_slot(node, 2u);
    if (!runtime_expr && expr_mentions_local_let(rhs))
        atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);
    add_func_body_len(owner_fn, len);
    publish_fragment(token, len, uint4(kind, target_decl, value, op), aux);
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
    if (!valid_node(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_assign(node, hir_token_pos[node]);
}
