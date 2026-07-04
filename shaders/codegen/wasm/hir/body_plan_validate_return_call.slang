// Parallel validation and planning for scalar WASM return direct-call expressions.

import atomics;
import body_common;
import body_plan_validate_common;

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

void validate_main_return_call(uint node, uint token)
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

    uint return_call_node = INVALID;
    uint return_atom_node = INVALID;
    uint return_op = 0u;
    uint return_call_side = 0u;
    uint binary_return_len = 0u;
    if (return_binary_direct_call_fragment_and_len(
            node,
            return_call_node,
            return_atom_node,
            return_op,
            return_call_side,
            binary_return_len))
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
        add_func_body_len(owner_fn, binary_return_len);
        publish_fragment(
            token,
            binary_return_len,
            uint4(
                BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32,
                return_call_node,
                return_atom_node,
                return_op | (return_call_side << 8u)),
            direct_call_aux(return_call_node));
        return;
    }

    uint return_expr_node = INVALID;
    uint return_len = 0u;
    if (return_direct_call_fragment_and_len(node, return_expr_node, return_len))
    {
        atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
        add_func_body_len(owner_fn, return_len);
        publish_fragment(
            token,
            return_len,
            uint4(
                BODY_FRAGMENT_RETURN_DIRECT_CALL_I32,
                return_expr_node,
                return_len,
                token),
            direct_call_aux(return_expr_node));
        return;
    }

    // Later return-call passes handle nested and aggregate direct-call forms.
    // Leave unsupported call returns unclaimed here so the most capable pass
    // owns the final accept/reject decision.
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
