// Parallel validation and aggregate planning for scalar WASM let statements.

import atomics;
import body_common;
import body_plan_validate_common;

static const uint LANGUAGE_SYMBOL_I32_TO_F32 = 28u;
static const uint BODY_FRAGMENT_LET_CONVERSION_EXPR_I32 = 50u;
static const uint BODY_FRAGMENT_IF_OPEN_CALL_EXPR_I32 = 51u;

bool wasm_call_expr_record(uint node, out uint wasm_func_index, out uint arg_count)
{
    wasm_func_index = INVALID;
    arg_count = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return false;
    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_READ_I32) ||
        token_has_language_name(fn_token, LANGUAGE_SYMBOL_READ_I32))
        wasm_func_index = WASM_STD_READ_I32_FUNC_INDEX;
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_TEXT) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_TEXT))
        wasm_func_index = WASM_STD_WRITE_TEXT_FUNC_INDEX;
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_I32) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_I32))
        wasm_func_index = WASM_STD_WRITE_I32_FUNC_INDEX;
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_BYTE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_BYTE))
        wasm_func_index = WASM_STD_WRITE_BYTE_FUNC_INDEX;
    else if (token_has_language_name(callee_token, LANGUAGE_SYMBOL_WRITE_NEWLINE) ||
             token_has_language_name(fn_token, LANGUAGE_SYMBOL_WRITE_NEWLINE))
        wasm_func_index = WASM_STD_WRITE_NEWLINE_FUNC_INDEX;
    else if (supported_function_token(fn_token))
        wasm_func_index = wasm_func_slot_by_token[fn_token] + WASM_IMPORT_FUNCTION_COUNT;
    else
        return false;
    arg_count = hir_call_arg_count[node];
    return true;
}

bool wasm_i32_to_f32_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_CALL_EXPR ||
        hir_call_arg_count[node] != 1u)
    {
        return false;
    }

    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    if ((!token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_TO_F32) &&
         !token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_TO_F32)) ||
        call_return_type_for_call(node, callee_token, fn_token) != TY_FLOAT)
    {
        return false;
    }

    uint arg_len = 0u;
    if (!expr_tree_and_len(direct_call_arg_node(node, 0u), arg_len))
        return false;
    len = arg_len + 1u;
    return true;
}

// Size a scalar expression tree whose leaves may include direct calls. The
// traversal is bounded per HIR expression and runs independently for every
// candidate let, while byte scatter remains parallel over the emitted body.
bool expr_tree_with_calls_and_len(uint root_node, out uint len)
{
    len = 0u;

    uint nodes[MAX_EXPR_EMIT_STACK];
    uint states[MAX_EXPR_EMIT_STACK];
    uint lens[MAX_EXPR_EMIT_STACK];
    uint sp = 0u;
    uint lsp = 0u;
    if (!push_expr_len_node(nodes, states, sp, root_node))
        return false;

    for (uint step = 0u; step < MAX_EXPR_EMIT_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        uint state = states[sp - 1u];
        uint leaf_len = 0u;
        if (state == 0u &&
            (expr_non_call_atom_and_len(node, leaf_len) ||
             string_value_expr_and_len(node, leaf_len) ||
             wasm_i32_to_f32_expr_and_len(node, leaf_len)))
        {
            if (lsp >= MAX_EXPR_EMIT_STACK)
                return false;
            lens[lsp] = leaf_len;
            lsp += 1u;
            sp -= 1u;
            continue;
        }

        uint call_index = INVALID;
        uint call_arg_count = 0u;
        if (wasm_call_expr_record(node, call_index, call_arg_count))
        {
            if (state < call_arg_count)
            {
                states[sp - 1u] = state + 1u;
                if (!push_expr_len_node(
                        nodes,
                        states,
                        sp,
                        direct_call_arg_node(resolve_expr_node(node), state)))
                    return false;
                continue;
            }
            if (lsp < call_arg_count)
                return false;
            uint call_len = 1u + u32_leb_len(call_index);
            for (uint i = 0u; i < call_arg_count; i += 1u)
                call_len += lens[lsp - call_arg_count + i];
            lsp -= call_arg_count;
            if (lsp >= MAX_EXPR_EMIT_STACK)
                return false;
            lens[lsp] = call_len;
            lsp += 1u;
            sp -= 1u;
            continue;
        }

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (state == 0u)
            {
                states[sp - 1u] = 1u;
                if (!push_expr_len_node(
                        nodes,
                        states,
                        sp,
                        expr_record_slot(node, EXPR_RECORD_LEFT)))
                    return false;
                continue;
            }
            if (lsp < 1u)
                return false;
            lens[lsp - 1u] +=
                form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u);
            sp -= 1u;
            continue;
        }

        if (!expr_binary_op_supported(form) || expr_binary_op_byte(form) == 0u)
            return false;
        if (state == 0u)
        {
            states[sp - 1u] = 1u;
            if (!push_expr_len_node(
                    nodes,
                    states,
                    sp,
                    expr_record_slot(node, EXPR_RECORD_LEFT)))
                return false;
            continue;
        }
        if (state == 1u)
        {
            states[sp - 1u] = 2u;
            if (!push_expr_len_node(
                    nodes,
                    states,
                    sp,
                    expr_record_slot(node, EXPR_RECORD_RIGHT)))
                return false;
            continue;
        }
        if (lsp < 2u)
            return false;
        uint right_len = lens[lsp - 1u];
        uint left_len = lens[lsp - 2u];
        lsp -= 1u;
        lens[lsp - 1u] = left_len + right_len + 1u;
        sp -= 1u;
    }

    if (sp != 0u || lsp != 1u)
        return false;
    len = lens[0u];
    return len != 0u;
}

bool supported_let_composite_call_fragment(
    uint node,
    out uint local_index,
    out uint expr_node,
    out uint len)
{
    local_index = INVALID;
    expr_node = INVALID;
    len = 0u;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    uint decl_token = stmt_record_slot(node, 1u);
    expr_node = stmt_record_slot(node, 2u);
    uint expr_len = 0u;
    if (!valid_token(decl_token) ||
        !valid_node(expr_node) ||
        !expr_tree_with_calls_and_len(expr_node, expr_len))
    {
        return false;
    }

    uint local_ty = local_decl_initializer_expr_type(expr_node);
    if (local_ty == TY_UNKNOWN)
        local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN)
        local_ty = TY_INT;
    if (!function_non_param_local_index_for_type(
            decl_token,
            node_enclosing_fn_token(node),
            local_ty,
            local_index))
        return false;
    len = expr_len + local_set_len(local_index);
    return true;
}

bool expr_tree_contains_call(uint root_node)
{
    uint nodes[MAX_EXPR_EMIT_STACK];
    uint sp = 1u;
    nodes[0u] = root_node;
    for (uint step = 0u; step < MAX_EXPR_EMIT_STEPS; step += 1u)
    {
        if (sp == 0u)
            return false;
        uint node = nodes[sp - 1u];
        sp -= 1u;
        node = resolve_expr_node(node);
        if (!valid_node(node))
            continue;
        if (hir_kind[node] == HIR_CALL_EXPR)
            return true;
        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (sp >= MAX_EXPR_EMIT_STACK)
                return false;
            nodes[sp++] = expr_record_slot(node, EXPR_RECORD_LEFT);
        }
        else if (expr_binary_op_supported(form))
        {
            if (sp + 2u > MAX_EXPR_EMIT_STACK)
                return false;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
            nodes[sp + 1u] = expr_record_slot(node, EXPR_RECORD_RIGHT);
            sp += 2u;
        }
    }
    return false;
}

void validate_main_if_call(uint node, uint token)
{
    if (hir_kind[node] != HIR_IF_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_IF ||
        !expr_tree_contains_call(stmt_record_slot(node, 1u)))
    {
        return;
    }

    uint owner_fn = node_enclosing_fn_token(node);
    uint condition_node = stmt_record_slot(node, 1u);
    uint condition_len = 0u;
    uint end_token = INVALID;
    uint end_len = 0u;
    uint else_token = INVALID;
    uint else_len = 0u;
    if (!valid_token(token) ||
        !expr_tree_with_calls_and_len(condition_node, condition_len) ||
        !if_end_token_and_len(node, end_token, end_len) ||
        (valid_node(stmt_record_slot(node, 3u)) &&
         !if_else_token_and_len(node, else_token, else_len)))
    {
        publish_func_invalid(owner_fn, valid_token(token) ? token : INVALID);
        return;
    }

    uint open_len = condition_len + 2u;
    add_func_body_len(owner_fn, open_len + else_len + end_len);
    publish_fragment(
        token,
        open_len,
        uint4(BODY_FRAGMENT_IF_OPEN_CALL_EXPR_I32, condition_node, open_len, token),
        uint4(INVALID, 0u, 0u, 0u));
    if (else_len != 0u)
    {
        publish_fragment(
            else_token,
            else_len,
            uint4(BODY_FRAGMENT_IF_ELSE, 0u, 0u, else_token),
            uint4(INVALID, 0u, 0u, 0u));
    }
    publish_fragment(
        end_token,
        end_len,
        uint4(BODY_FRAGMENT_IF_END, 0u, 0u, end_token),
        uint4(INVALID, 0u, 0u, 0u));
    publish_body_features(BODY_FEATURE_MEMBER_EXPR_SCATTER);
}

bool supported_let_string_literal_fragment(
    uint node,
    out uint decl_token,
    out uint ptr_local,
    out uint len_local,
    out uint ptr_value,
    out uint len_value,
    out uint ptr_fragment_len,
    out uint len_fragment_len)
{
    decl_token = INVALID;
    ptr_local = INVALID;
    len_local = INVALID;
    ptr_value = 0u;
    len_value = 0u;
    ptr_fragment_len = 0u;
    len_fragment_len = 0u;

    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return false;
    }

    decl_token = stmt_record_slot(node, 1u);
    uint init_expr = stmt_record_slot(node, 2u);
    uint owner_fn = node_enclosing_fn_token(node);
    if (!valid_token(decl_token) ||
        visible_type_for_token(decl_token) != TY_STRING ||
        expr_mentions_local_let(init_expr) ||
        !string_literal_ptr_len(init_expr, ptr_value, len_value) ||
        !function_non_param_local_index_for_type(decl_token, owner_fn, TY_INT, ptr_local) ||
        !function_string_len_local_index(decl_token, owner_fn, len_local))
    {
        return false;
    }

    ptr_fragment_len = 1u + i32_sleb_len(ptr_value) + local_set_len(ptr_local);
    len_fragment_len = 1u + i32_sleb_len(len_value) + local_set_len(len_local);
    return true;
}

void validate_main_let(uint node, uint token)
{
    uint owner_fn = node_enclosing_fn_token(node);
    if (hir_kind[node] == HIR_NONE)
        return;

    uint stmt_kind = stmt_record_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_NONE || hir_kind[node] == HIR_ARRAY_EXPR)
        return;

    if (!valid_token(token))
    {
        publish_func_invalid(owner_fn, INVALID);
        return;
    }

    if (stmt_kind == STMT_RECORD_KIND_LET && hir_kind[node] == HIR_LET_STMT)
    {
        uint raw_init_expr = resolve_expr_node(stmt_record_slot(node, 2u));
        if (valid_node(raw_init_expr) && hir_kind[raw_init_expr] == HIR_ARRAY_EXPR)
            return;
        uint raw_decl_token = stmt_record_slot(node, 1u);
        if (valid_token(raw_decl_token) &&
            (visible_type_for_token(raw_decl_token) >= TY_ARRAY_BASE ||
             wasm_agg_local_width_by_token[raw_decl_token] != 0u))
            return;
        if (valid_token(raw_decl_token) &&
            visible_type_for_token(raw_decl_token) >= TY_ARRAY_BASE &&
            valid_node(raw_init_expr) &&
            hir_kind[raw_init_expr] == HIR_CALL_EXPR)
        {
            return;
        }
        if (valid_node(raw_init_expr) && hir_kind[raw_init_expr] == HIR_CALL_EXPR)
        {
            uint conversion_len = 0u;
            if (!wasm_i32_to_f32_expr_and_len(raw_init_expr, conversion_len))
                return;
        }
        if (valid_node(raw_init_expr) && expr_binary_op_supported(expr_form(raw_init_expr)))
        {
            uint raw_left = resolve_expr_node(expr_record_slot(raw_init_expr, EXPR_RECORD_LEFT));
            uint raw_right = resolve_expr_node(expr_record_slot(raw_init_expr, EXPR_RECORD_RIGHT));
            uint conversion_len = 0u;
            bool unsupported_left_call =
                valid_node(raw_left) &&
                hir_kind[raw_left] == HIR_CALL_EXPR &&
                !wasm_i32_to_f32_expr_and_len(raw_left, conversion_len);
            bool unsupported_right_call =
                valid_node(raw_right) &&
                hir_kind[raw_right] == HIR_CALL_EXPR &&
                !wasm_i32_to_f32_expr_and_len(raw_right, conversion_len);
            if (unsupported_left_call || unsupported_right_call)
            {
                return;
            }
        }

        uint decl_token = INVALID;
        uint expr_node = INVALID;
        uint value = 0u;
        uint len = 0u;
        uint4 aux = uint4(INVALID, 0u, 0u, 0u);
        uint ptr_local = INVALID;
        uint len_local = INVALID;
        uint ptr_value = 0u;
        uint len_value = 0u;
        uint ptr_fragment_len = 0u;
        uint len_fragment_len = 0u;
        uint kind = BODY_FRAGMENT_LET_CONST_I32;
        uint meta_w = token;
        bool runtime_expr = true;
        if (supported_let_string_literal_fragment(
                node,
                decl_token,
                ptr_local,
                len_local,
                ptr_value,
                len_value,
                ptr_fragment_len,
                len_fragment_len))
        {
            add_func_local_token(owner_fn, decl_token);
            add_func_body_len(owner_fn, ptr_fragment_len + len_fragment_len);
            publish_fragment_slot(
                token * 2u,
                ptr_fragment_len,
                uint4(BODY_FRAGMENT_LET_CONST_I32, ptr_local, ptr_value, token),
                aux);
            publish_fragment_slot(
                token * 2u + 1u,
                len_fragment_len,
                uint4(BODY_FRAGMENT_LET_CONST_I32, len_local, len_value, token),
                aux);
            return;
        }
        else if (supported_let_const_fragment(node, decl_token, value, len))
        {
            runtime_expr = false;
            kind = BODY_FRAGMENT_LET_CONST_I32;
            expr_node = value;
        }
        else if (supported_let_expr_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_EXPR_I32;
            publish_body_features(BODY_FEATURE_MEMBER_EXPR_SCATTER);
        }
        else if (supported_let_composite_call_fragment(node, decl_token, expr_node, len))
        {
            kind = BODY_FRAGMENT_LET_CONVERSION_EXPR_I32;
            publish_body_features(BODY_FEATURE_MEMBER_EXPR_SCATTER);
        }
        else
        {
            publish_func_invalid(owner_fn, token);
            return;
        }

        uint init_expr = stmt_record_slot(node, 2u);
        if (!runtime_expr && expr_mentions_local_let(init_expr))
            atomic_u32_add(body_plan, BODY_PLAN_LOCAL_CONST_EXPR_COUNT, 1u);

        add_func_local_token(owner_fn, stmt_record_slot(node, 1u));
        add_func_body_len(owner_fn, len);
        publish_fragment(token, len, uint4(kind, decl_token, expr_node, meta_w), aux);
        return;
    }

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
    validate_main_if_call(node, token);
    validate_main_let(node, token);
}
