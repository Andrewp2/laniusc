// Legacy raw-node contribution contract retained only while body fragments
// still carry raw parser identities.

import body_common;
import call_relocation;
import expr_emission_common;

static const uint LANGUAGE_SYMBOL_I32_TO_F32 = 28u;

public bool raw_wasm_call_expr_record(uint node, out uint wasm_func_index, out uint arg_count)
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
    else if (supported_call_target_token(fn_token))
        wasm_func_index = wasm_call_target_for_call(node, fn_token);
    else
        return false;
    arg_count = hir_call_arg_count[node];
    return true;
}

bool raw_wasm_i32_to_f32_expr_node(uint node)
{
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR ||
        hir_call_arg_count[node] != 1u)
        return false;
    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    return (token_has_language_name(callee_token, LANGUAGE_SYMBOL_I32_TO_F32) ||
            token_has_language_name(fn_token, LANGUAGE_SYMBOL_I32_TO_F32)) &&
           call_return_type_for_call(node, callee_token, fn_token) == TY_FLOAT;
}

public bool raw_wasm_expr_node_contribution(
    uint node,
    bool aggregate_address_context,
    out uint len,
    out uint2 emission)
{
    len = 0u;
    emission = wasm_expr_no_emission();
    if (!valid_node(node)) return false;
    uint form = expr_form(node);
    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_name = hir_member_name_token[node];
        uint field_index = valid_token(member_name)
                               ? member_result_field_index[member_name]
                               : INVALID;
        if (field_index == INVALID) return valid_token(member_name);
        uint offset = field_index * 4u;
        len = 2u + u32_leb_len(offset);
        emission = wasm_expr_load_emission(
            offset,
            visible_type_for_token(member_name) == TY_FLOAT);
        return true;
    }
    if (form == HIR_EXPR_FORWARD) return false;
    if (hir_kind[node] == HIR_INDEX_EXPR && form == HIR_EXPR_INDEX_FORM)
    {
        len = 7u;
        uint token = hir_token_pos[node];
        emission = wasm_expr_index_load_emission(
            valid_token(token) && visible_type_for_token(token) == TY_FLOAT);
        return true;
    }
    if (raw_wasm_i32_to_f32_expr_node(node))
    {
        len = 1u;
        emission = wasm_expr_i32_to_f32_emission();
        return true;
    }
    uint call_index = INVALID;
    uint arg_count = 0u;
    if (raw_wasm_call_expr_record(node, call_index, arg_count))
    {
        len = 1u + wasm_call_index_len(call_index);
        emission = wasm_expr_call_emission(call_index);
        return true;
    }
    if (aggregate_address_context)
    {
        uint opcode = 0u;
        uint operand = 0u;
        uint address_len = 0u;
        if (aggregate_name_address_expr_plan(node, opcode, operand, address_len))
        {
            len = address_len;
            emission = opcode == WASM_LOCAL_GET
                           ? wasm_expr_local_get_emission(operand)
                           : wasm_expr_i32_const_emission(operand);
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
    if (form == HIR_EXPR_NONE) return false;
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
