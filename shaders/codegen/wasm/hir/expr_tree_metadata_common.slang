// Target-independent expression-forest rows reduced to WASM byte contributions.

import compact_expr_common;
import host_call_target_common;
import call_relocation;
import expr_emission_common;

static const uint LANGUAGE_SYMBOL_I32_TO_F32 = 28u;

public bool wasm_call_expr_record(uint node, out uint wasm_func_index, out uint arg_count)
{
    wasm_func_index = INVALID;
    arg_count = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_CALL_EXPR)
        return false;
    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    uint return_ty = call_return_type_for_call(node, callee_token, fn_token);
    bool statement_void = return_ty == TY_VOID &&
        (compact_hir_payload[node].d & HIR_CALL_CONTEXT_STMT_BIT) != 0u;
    if (!type_is_i32_value(return_ty) && return_ty != TY_FLOAT && !statement_void)
        return false;
    if (wasm_host_import_for_call(callee_token, fn_token, wasm_func_index))
    {
        // The fixed runtime ABI is resolved from semantic language names, not
        // from a statement or source shape.
    }
    else if (supported_call_target_token(fn_token))
        wasm_func_index = wasm_call_target_for_call(node, fn_token);
    else
        return false;
    arg_count = compact_hir_payload[node].c;
    return true;
}

public bool wasm_i32_to_f32_expr_node(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) ||
        compact_hir_core[node].kind != HIR_CALL_EXPR ||
        compact_hir_payload[node].c != 1u)
    {
        return false;
    }
    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    return (token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_TO_F32) ||
            token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_TO_F32)) &&
           call_return_type_for_call(node, callee_token, fn_token) == TY_FLOAT;
}

// Returns this row's own emitted byte count. Child rows contribute separately.
// Forwarding and non-expression HIR rows are deliberately inactive so aliases
// cannot count the same semantic expression twice.
public bool wasm_expr_node_contribution(
    uint node,
    bool aggregate_address_context,
    out uint len,
    out uint2 emission)
{
    len = 0u;
    emission = wasm_expr_no_emission();
    if (!valid_node(node))
        return false;
    uint form = expr_form(node);
    // Member HIR nodes use a forwarding expression record for their receiver,
    // but the member row itself is semantic: it emits the field load after the
    // receiver subtree. Handle it before filtering generic forwarding aliases.
    if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
    {
        uint member_name = compact_hir_payload[node].c;
        uint field_index = valid_token(member_name)
                               ? member_result_field_index[member_name]
                               : INVALID;
        // Method-callee member nodes carry the receiver edge but do not emit
        // a field load of their own.
        if (field_index == INVALID)
            return valid_token(member_name);
        uint offset = field_index * 4u;
        len = 2u + u32_leb_len(offset);
        emission = wasm_expr_load_emission(
            offset,
            visible_type_for_token(member_name) == TY_FLOAT);
        return true;
    }
    if (form == HIR_EXPR_FORWARD)
        return false;
    if (compact_hir_core[node].kind == HIR_INDEX_EXPR && form == HIR_EXPR_INDEX_FORM)
    {
        len = 7u;
        uint token = compact_hir_core[node].token_start;
        emission = wasm_expr_index_load_emission(
            valid_token(token) && visible_type_for_token(token) == TY_FLOAT);
        return true;
    }
    if (wasm_i32_to_f32_expr_node(node))
    {
        len = 1u;
        emission = wasm_expr_i32_to_f32_emission();
        return true;
    }
    uint call_index = INVALID;
    uint arg_count = 0u;
    if (wasm_call_expr_record(node, call_index, arg_count))
    {
        // Lanius declaration calls use a padded five-byte immediate carrying
        // a relocation marker. Runtime imports retain minimal varuint32
        // encoding. Keep the contribution span identical to byte emission so
        // nested-call subtree ownership cannot cross into its parent call.
        len = 1u + wasm_call_index_len(call_index);
        emission = wasm_expr_call_emission(call_index);
        return true;
    }
    // A call node's payload.a is its dense callee HIR ID, not an expression
    // form. An unsupported call remains unsupported instead of allowing that
    // identity to collide with an arithmetic-form number.
    if (compact_hir_core[node].kind == HIR_CALL_EXPR)
        return false;
    if (aggregate_address_context)
    {
        uint address_opcode = 0u;
        uint address_operand = 0u;
        uint address_len = 0u;
        if (aggregate_name_address_expr_plan(
                node,
                address_opcode,
                address_operand,
                address_len))
        {
            len = address_len;
            emission = address_opcode == WASM_LOCAL_GET
                           ? wasm_expr_local_get_emission(address_operand)
                           : wasm_expr_i32_const_emission(address_operand);
            return true;
        }
    }
    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len) ||
        string_value_expr_and_len(node, atom_len))
    {
        len = atom_len;
        return true;
    }
    if (form == HIR_EXPR_NONE)
        return false;
    if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
    {
        len = form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u);
        return true;
    }
    if (expr_binary_op_supported(form) && expr_binary_op_byte(form) != 0u)
    {
        len = 1u;
        return true;
    }
    return false;
}
