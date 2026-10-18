// Common argument-value projection for collection and claim emission.
// An argument's type is its expression's synthesized reference: the node's
// published slot (a call's closed result), else the shared expression rule
// that 03g publishes (inference_expression_reference.slang), read through the
// including kernel's graph. No reader here keeps its own form list.
// The including kernel defines ARGUMENT_TYPE_GRAPH (the graph it reads type
// rows through) and parameter_type_capacity().
import type_checker.argument_context;
#include "argument_result_reference.slang"
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
import primitive_types;
#define INFERENCE_INDEX_GRAPH ARGUMENT_TYPE_GRAPH
#define INFERENCE_TYPE_CAPACITY() parameter_type_capacity()
#define INFERENCE_CALL_RESULT_CLOSED(instance) concrete_instance_is_closed<ARGUMENT_TYPE_GRAPH, CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(instance, parameter_type_capacity(), gParams.n_tokens)
#include "../inference_expression_reference.slang"

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

// payload.a is kind-dependent (parser/hir/canonical/core.slang): a call row
// stores its callee node and a match row its scrutinee there, and either ID
// can equal a form tag. A call whose callee is node 11 (HIR_EXPR_LE) read as
// a bool argument before its result was known.
uint expr_form(uint node)
{
    if (!valid_node(node)) return HIR_EXPR_NONE;
    uint kind = compact_hir_core[node].kind;
    if (kind == HIR_CALL_EXPR || kind == HIR_MATCH_EXPR) return HIR_EXPR_NONE;
    return expr_record_slot(node, HIR_EXPR_RECORD_FORM);
}

uint resolve_expr(uint node)
{
    return argument_context_root(node, active_hir_node_count(),
        compact_hir_core, compact_hir_payload);
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

bool argument_value_reference(uint node, out uint tag, out uint payload)
{
    node = resolve_expr(node);
    // The published slot carries results that only later passes produce
    // (calls, array literals); the shared rule covers every other form now.
    return argument_result_reference(node, tag, payload) ||
        inference_value_reference(node, tag, payload);
}
