// Parallel validation and aggregate planning for scalar WASM assignments.

import atomics;
import body_common;
import body_plan_validate_common;

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
    if (body_plan[BODY_PLAN_MAIN_COUNT] != 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_assign(node, hir_token_pos[node]);
}
