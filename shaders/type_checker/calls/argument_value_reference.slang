// Common argument-value projection for collection and claim emission.
// Accepted expression/field references take precedence over declaration hints.
// Scalar codes are used only for scalar expressions and never reconstruct a
// compound type or a generic binding.
import type_checker.argument_context;
#include "argument_result_reference.slang"
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> literal_context_type_by_hir;
import primitive_types;

uint expr_record_slot(uint node, uint slot)
{
    if (!valid_node(node))
        return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == HIR_EXPR_RECORD_FORM) return payload.a;
    if (slot == HIR_EXPR_RECORD_LEFT) return payload.b;
    if (slot == HIR_EXPR_RECORD_RIGHT) return payload.c;
    return payload.d;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return argument_context_root(node, active_hir_node_count(),
        compact_hir_core, compact_hir_payload);
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token];
}

uint inferred_call_return_type(uint callee_token)
{
    if (!valid_token(callee_token)) return TY_UNKNOWN;
    // A return with a type-graph origin needs its complete accepted reference.
    // Its legacy code can be a native storage projection: &Cell<T> has the
    // pointer code before specialization, which is not a scalar ptr argument.
    // argument_result_reference supplies the checked result when it is ready.
    if (call_return_type_token[callee_token] != INVALID) return TY_UNKNOWN;
    uint type = call_return_type[callee_token];
    return type < TY_GENERIC_BASE ? type : TY_UNKNOWN;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_node].c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = compact_hir_payload[callee_node].d;
    if (!valid_token(callee_token))
        callee_token = compact_hir_core[callee_node].token_start;
    if (!valid_token(callee_token))
        callee_token = compact_hir_core[call_node].token_start;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint direct_node_type_no_nested_call(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = hir_scalar_type_for_hir(compact_hir_core[node].kind, expr_form(node));
    if (lit != TY_UNKNOWN)
    {
        uint context = literal_context_type_by_hir[node];
        if ((expr_form(node) == HIR_EXPR_INT && scalar_is_integer(context)) ||
            (expr_form(node) == HIR_EXPR_FLOAT && scalar_is_float(context))) return context;
        return lit;
    }

    uint token = compact_hir_core[node].token_start;
    if (compact_hir_core[node].kind == HIR_NAME_EXPR)
    {
        uint value_token = expr_value_token(node);
        if (valid_token(value_token))
            token = value_token;
        return visible_type_for_token(token);
    }

    if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[node].c;
        return visible_type_for_token(member_token);
    }

    if (compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR)
        return visible_type_for_token(compact_hir_core[node].token_start);

    if (compact_hir_core[node].kind == HIR_INDEX_EXPR)
    {
        uint tag; uint payload;
#ifdef ARGUMENT_TYPE_GRAPH
        // The including kernel reads the type rows through its own graph.
        if (checked_named_index_reference<ARGUMENT_TYPE_GRAPH>(node, active_hir_node_count(), gParams.n_tokens,
            compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
            decl_type_ref_payload, parameter_type_capacity(), tag, payload) ||
            checked_member_index_reference<ARGUMENT_TYPE_GRAPH>(node, active_hir_node_count(), gParams.n_tokens,
                compact_hir_core, compact_hir_payload, member_result_ref_tag, member_result_ref_payload,
                parameter_type_capacity(), tag, payload))
            return leaf_type_code_for_ref(tag, payload);
#else
        if (checked_named_index_reference(node, active_hir_node_count(), gParams.n_tokens,
            compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
            decl_type_ref_payload, type_instance_kind, type_instance_elem_ref_tag,
            type_instance_elem_ref_payload, tag, payload) ||
            checked_member_index_reference(node, active_hir_node_count(), gParams.n_tokens,
                compact_hir_core, compact_hir_payload, member_result_ref_tag, member_result_ref_payload,
                type_instance_kind, type_instance_elem_ref_tag, type_instance_elem_ref_payload, tag, payload))
            return leaf_type_code_for_ref(tag, payload);
#endif
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;
    }
    if (compact_hir_core[node].kind == HIR_MATCH_EXPR)
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;

    if (compact_hir_core[node].kind == HIR_CALL_EXPR)
    {
        uint callee_token = callee_token_for_hir_call(node);
        if (!valid_token(callee_token))
            callee_token = compact_hir_core[node].token_start;
        return inferred_call_return_type(callee_token);
    }

    return TY_UNKNOWN;
}

uint expr_type_no_nested_call(uint result_node)
{
    uint node = resolve_expr(result_node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    bool arithmetic = form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_DIV;
    // One direct-type site: the node itself, then an arithmetic node's
    // left and right operands.
    uint left_ty = TY_UNKNOWN;
    uint right_ty = TY_UNKNOWN;
    for (uint operand = 0u; operand < 3u; operand++)
    {
        uint current = operand == 0u ? node : resolve_expr(expr_record_slot(node,
            operand == 1u ? HIR_EXPR_RECORD_LEFT : HIR_EXPR_RECORD_RIGHT));
        uint ty = direct_node_type_no_nested_call(current);
        if (operand == 0u)
        {
            if (ty != TY_UNKNOWN) return ty;
            if (!arithmetic) break;
        }
        else if (operand == 1u) left_ty = ty;
        else right_ty = ty;
    }

    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_value_token(node);
        if (!valid_token(token))
            token = compact_hir_core[node].token_start;
        return visible_type_for_token(token);
    }

    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return TY_BOOL;

    if (arithmetic)
        return scalar_is_float(left_ty) ? left_ty : scalar_is_float(right_ty) ? right_ty :
            scalar_is_integer(left_ty) ? left_ty : scalar_is_integer(right_ty) ? right_ty : TY_UNKNOWN;

    if (form == HIR_EXPR_MOD ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

uint generic_slot_for_type_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_EXTERNAL_GENERIC)
        return payload;
    if (tag != TYPE_REF_GENERIC_PARAM || !valid_token(payload))
        return INVALID;
    uint slot = type_generic_param_slot_by_token[payload];
    if (slot != INVALID)
        return slot;
    uint declaration = visible_decl[payload];
    return valid_token(declaration)
        ? type_generic_param_slot_by_token[declaration]
        : INVALID;
}

uint leaf_type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    uint slot = generic_slot_for_type_ref(tag, payload);
    return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
}

uint direct_name_expr_token(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node))
        return INVALID;
    if (expr_form(node) != HIR_EXPR_NAME &&
        compact_hir_core[node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint token = expr_value_token(node);
    if (!valid_token(token))
        token = compact_hir_core[node].token_start;
    return valid_token(token) ? token : INVALID;
}

#include "../named_expression_reference.slang"
bool read_decl_type_ref(uint token_i, out uint tag, out uint payload)
{
    return named_expression_reference(token_i, tag, payload);
}

bool arg_decl_type_ref(uint arg_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (argument_result_reference(resolve_expr(arg_node), tag, payload)) return true;
    uint node = resolve_expr(arg_node);
    if (valid_node(node) && compact_hir_core[node].kind == HIR_MEMBER_EXPR)
    {
        // The member chain has already applied the receiver environment.
        // Its projected reference is authoritative before expression-artifact
        // publication and can name a private generated application.
        uint token = compact_hir_payload[node].c;
        if (valid_token(token))
        {
            tag = member_result_ref_tag[token];
            payload = member_result_ref_payload[token];
            if (tag != TYPE_REF_INVALID && payload != INVALID) return true;
        }
    }
#ifdef ARGUMENT_TYPE_GRAPH
    if (checked_named_index_reference<ARGUMENT_TYPE_GRAPH>(arg_node, active_hir_node_count(), gParams.n_tokens,
        compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
        decl_type_ref_payload, parameter_type_capacity(), tag, payload) ||
        checked_member_index_reference<ARGUMENT_TYPE_GRAPH>(arg_node, active_hir_node_count(), gParams.n_tokens,
            compact_hir_core, compact_hir_payload, member_result_ref_tag, member_result_ref_payload,
            parameter_type_capacity(), tag, payload)) return true;
#else
    if (checked_named_index_reference(arg_node, active_hir_node_count(), gParams.n_tokens,
        compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
        decl_type_ref_payload, type_instance_kind, type_instance_elem_ref_tag,
        type_instance_elem_ref_payload, tag, payload) ||
        checked_member_index_reference(arg_node, active_hir_node_count(), gParams.n_tokens,
            compact_hir_core, compact_hir_payload, member_result_ref_tag, member_result_ref_payload,
            type_instance_kind, type_instance_elem_ref_tag, type_instance_elem_ref_payload, tag, payload)) return true;
#endif
    uint token = direct_name_expr_token(arg_node);
    return read_decl_type_ref(token, tag, payload);
}

bool argument_value_reference(uint node, out uint tag, out uint payload)
{
    node = resolve_expr(node);
    bool known = arg_decl_type_ref(node, tag, payload);
    // Page-local imported templates are not accepted caller-side values.
    if (known && (tag == 5u || tag == 6u))
    { tag = 0u; payload = INVALID; return false; }
    // Only record literals have an early semantic-artifact producer. Other
    // artifact rows are published after inference and may still contain a
    // previous workspace job. Their accepted inputs are projected above.
    if (!known && valid_node(node) && compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR &&
        semantic_expr_ref_tag_by_hir[node] != 0u)
    {
        tag = semantic_expr_ref_tag_by_hir[node];
        payload = semantic_expr_ref_payload_by_hir[node];
        known = (tag == 1u || tag == 2u || tag == 3u) && payload != INVALID;
    }
    if (!known)
    {
        uint scalar = expr_type_no_nested_call(node);
        if (scalar != 0u && scalar < 128u)
        { tag = 1u; payload = scalar; return true; }
    }
    return known;
}
