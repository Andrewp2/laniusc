// Parallel validation and aggregate planning for scalar WASM control statements.

import atomics;
import body_common;
import body_plan_validate_common;

void validate_main_control(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    uint stmt_kind = stmt_record_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_NONE ||
        stmt_kind == STMT_RECORD_KIND_LET ||
        stmt_kind == STMT_RECORD_KIND_RETURN ||
        stmt_kind == STMT_RECORD_KIND_ASSIGN)
    {
        return;
    }

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_IF && hir_kind[node] == HIR_IF_STMT)
    {
        // Dense-HIR control planning owns scalar IF statements.
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_WHILE && hir_kind[node] == HIR_WHILE_STMT)
    {
        // Dense-HIR control planning owns scalar WHILE statements.
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_FOR &&
        (hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT))
    {
        // Dense-HIR control planning owns numeric ranges; aggregate range
        // planning owns array and aggregate iterables.
        return;
    }

    if ((stmt_kind == STMT_RECORD_KIND_BREAK && hir_kind[node] == HIR_BREAK_STMT) ||
        (stmt_kind == STMT_RECORD_KIND_CONTINUE && hir_kind[node] == HIR_CONTINUE_STMT))
    {
        // Dense-HIR control planning owns loop branches.
        return;
    }

    publish_func_invalid(owner_fn, token);
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
    if (hir_kind[node] == HIR_ARRAY_EXPR || hir_kind[node] == HIR_CALL_EXPR)
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;
    validate_main_control(node, hir_token_pos[node]);
}
