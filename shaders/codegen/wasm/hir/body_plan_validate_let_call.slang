// Parallel validation and planning for scalar WASM direct-call let initializers.

import atomics;
import body_common;
import body_plan_validate_common;

bool let_direct_arg_expr_is_f32(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return false;
    if (expr_atom_is_f32(node))
        return true;
    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        return expr_atom_is_f32(expr_record_slot(node, EXPR_RECORD_LEFT));
    if (expr_binary_op_supported(form))
    {
        uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
        return expr_atom_is_f32(left) || expr_atom_is_f32(right);
    }
    return false;
}

uint let_binary_direct_call_op_byte(uint node, uint decl_token)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;
    uint form = expr_form(node);
    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    if (visible_type_for_token(decl_token) == TY_FLOAT ||
        let_direct_arg_expr_is_f32(left) ||
        let_direct_arg_expr_is_f32(right))
    {
        if (form == HIR_EXPR_EQ) return WASM_F32_EQ;
        if (form == HIR_EXPR_NE) return WASM_F32_NE;
        if (form == HIR_EXPR_LT) return WASM_F32_LT;
        if (form == HIR_EXPR_GT) return WASM_F32_GT;
        if (form == HIR_EXPR_LE) return WASM_F32_LE;
        if (form == HIR_EXPR_GE) return WASM_F32_GE;
        if (form == HIR_EXPR_ADD) return WASM_F32_ADD;
        if (form == HIR_EXPR_SUB) return WASM_F32_SUB;
        if (form == HIR_EXPR_MUL) return WASM_F32_MUL;
        if (form == HIR_EXPR_DIV) return WASM_F32_DIV;
        return 0u;
    }
    return expr_binary_op_byte(form);
}

bool let_binary_direct_call_record(
    uint node,
    uint decl_token,
    out uint call_node,
    out uint expr_node,
    out uint op,
    out uint len_without_args,
    out uint4 aux)
{
    call_node = INVALID;
    expr_node = INVALID;
    op = 0u;
    len_without_args = 0u;
    aux = uint4(INVALID, 0u, INVALID, 0u);
    node = resolve_expr_node(node);
    if (!valid_node(node) || !expr_binary_op_supported(expr_form(node)))
        return false;
    op = let_binary_direct_call_op_byte(node, decl_token);
    if (op == 0u)
        return false;

    uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
    uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
    uint right_expr_len = 0u;
    bool right_expr = direct_call_arg_expr_and_len(right, right_expr_len);
    call_node = resolve_expr_node(left);
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR || !right_expr)
        return false;

    aux = direct_call_aux(call_node);
    if (aux.x == INVALID)
        return false;

    expr_node = right;
    len_without_args = (1u + u32_leb_len(aux.x)) + right_expr_len + 1u;
    return true;
}

bool supported_let_binary_direct_call_fragment_local(
    uint node,
    out uint decl_token,
    out uint call_node,
    out uint expr_node,
    out uint op,
    out uint len,
    out uint4 aux)
{
    decl_token = INVALID;
    call_node = INVALID;
    expr_node = INVALID;
    op = 0u;
    len = 0u;
    aux = uint4(INVALID, 0u, INVALID, 0u);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    uint init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
    uint len_without_args = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(init_expr) ||
        !let_binary_direct_call_record(init_expr, decl_token, call_node, expr_node, op, len_without_args, aux))
    {
        return false;
    }

    uint local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = local_decl_initializer_expr_type(init_expr);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;

    uint local_index = INVALID;
    if (!function_non_param_local_index_for_type(
            decl_token,
            node_enclosing_fn_token(node),
            local_ty,
            local_index))
    {
        return false;
    }

    decl_token = local_index;
    len = len_without_args + local_set_len(local_index);
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
    if (!valid_node(init_expr))
        return;

    bool direct_call_init = hir_kind[init_expr] == HIR_CALL_EXPR;
    bool binary_direct_call_init = false;
    if (!direct_call_init && expr_binary_op_supported(expr_form(init_expr)))
    {
        uint left = resolve_expr_node(expr_record_slot(init_expr, EXPR_RECORD_LEFT));
        uint right = resolve_expr_node(expr_record_slot(init_expr, EXPR_RECORD_RIGHT));
        binary_direct_call_init =
            (valid_node(left) && hir_kind[left] == HIR_CALL_EXPR) ||
            (valid_node(right) && hir_kind[right] == HIR_CALL_EXPR);
    }
    if (!direct_call_init && !binary_direct_call_init)
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
    uint len = 0u;
    uint binary_call_node = INVALID;
    uint binary_expr_node = INVALID;
    uint binary_op = 0u;
    uint4 binary_aux = uint4(INVALID, 0u, INVALID, 0u);
    if (supported_let_binary_direct_call_fragment_local(
            node,
            decl_token,
            binary_call_node,
            binary_expr_node,
            binary_op,
            len,
            binary_aux))
    {
        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_body_len(owner_fn, len);
        uint4 aux = binary_aux;
        aux.w = binary_op;
        publish_fragment(
            token,
            len,
            uint4(BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32, decl_token, binary_call_node, binary_expr_node),
            aux);
        return;
    }

    if (!supported_let_direct_call_fragment(node, decl_token, expr_node, len))
    {
        return;
    }

    add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
    add_func_body_len(owner_fn, len);
    publish_fragment(
        token,
        len,
        uint4(BODY_FRAGMENT_LET_DIRECT_CALL_I32, decl_token, expr_node, token),
        direct_call_aux(expr_node));
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
