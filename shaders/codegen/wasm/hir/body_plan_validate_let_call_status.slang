// Reject scalar let call initializers not claimed by any let-call planner.

import atomics;
import body_common;
import body_plan_validate_common;

bool scalar_let_call_candidate(uint node)
{
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    uint decl_token = stmt_record_slot(node, 1u);
    if (!valid_token(decl_token))
        return true;
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE ||
        wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        return false;
    }

    uint init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
    return valid_node(init_expr) && hir_kind[init_expr] == HIR_CALL_EXPR;
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
    if (!scalar_let_call_candidate(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token) || body_fragment_len[token * 2u] == 0u)
        publish_func_invalid(owner_fn, valid_token(token) ? token : INVALID);
}
