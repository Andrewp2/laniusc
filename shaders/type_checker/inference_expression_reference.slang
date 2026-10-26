import primitive_types;
#include "named_expression_reference.slang"
// Included by fact producers with read-only or writable declaration columns.
// Read complete roots from earlier dispatches. Index chains are traversed from
// immutable roots; no lane reads another lane's partially published result.
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> literal_context_type_by_hir;
// An includer may check a call result's closure itself, for example by
// canonical ID after interning it; the default walks the checked graph.
#ifndef INFERENCE_CALL_RESULT_CLOSED
#define INFERENCE_CALL_RESULT_CLOSED(instance) checked_instance_is_closed(instance)
#endif
// The type rows an includer reads (checked or mutable graph).
#ifndef INFERENCE_TYPE_CAPACITY
#define INFERENCE_TYPE_CAPACITY() checked_type_capacity()
#endif
// An unsuffixed numeric literal, under at most one negation, that has no
// checked context yet. Its arithmetic peer supplies the operation's type.
bool inference_uncontexted_literal(uint node, uint count)
{
    if (node >= count) return false;
    if (compact_hir_core[node].kind == 17u && compact_hir_payload[node].a == 13u)
        node = compact_hir_payload[node].b;
    if (node >= count || compact_hir_core[node].kind != 23u) return false;
    uint form = compact_hir_payload[node].a;
    uint context = literal_context_type_by_hir[node];
    return (form == HIR_SEM_EXPR_INT && !scalar_is_integer(context)) ||
        (form == HIR_SEM_EXPR_FLOAT && !scalar_is_float(context));
}
bool inference_value_reference(uint node, out uint tag, out uint payload, bool current_match = true)
{
    static const uint INVALID_REF = 0xffffffffu;
    tag = 0u; payload = INVALID_REF;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint root; uint indices;
    checked_index_root(node, count, compact_hir_core, compact_hir_payload, root, indices);
    // These are parser-owned expression edges, not nested type graph nodes.
    // The acyclic HIR bounds this walk even for deeply nested arithmetic.
    for (uint step = 0u; step < count; step++)
    {
        if (root >= count) return false;
        HirCore core = compact_hir_core[root];
        HirPayload value = compact_hir_payload[root];
        if (core.kind == 20u)
        {
            uint indexed_root; uint additional_indices;
            if (!checked_index_root(root, count, compact_hir_core, compact_hir_payload,
                indexed_root, additional_indices) || additional_indices > 64u - indices)
                return false;
            indices += additional_indices;
            root = indexed_root;
            continue;
        }
        // Unsigned range tests (x - lo <= hi - lo) keep this shared walk small.
        if (core.kind - 16u <= 1u || core.kind == 14u)
        {
            uint form = value.a;
            if (form == 1u) { root = value.b; continue; }
            if (indices != 0u) return false;
            // true/false, not, comparisons, and logical and/or are bool.
            if (form - 4u <= 8u || form - 17u <= 1u)
            { tag = 1u; payload = 2u; break; }
            // Arithmetic inherits its checked operand type, as in scalar
            // projection. An unresolved operand must not become guessed i32.
            // A binary operation whose left operand is an uncontexted literal
            // takes the type of its right operand; a shift keeps its value's.
            if (form - 13u <= 3u || form - 19u <= 6u)
            {
                bool peer = form != 13u && form - 24u > 1u &&
                    inference_uncontexted_literal(value.b, count) &&
                    !inference_uncontexted_literal(value.c, count);
                root = peer ? value.c : value.b;
                continue;
            }
            // `value as T` has its target's checked reference, published at
            // the target type's first token (payload.d).
            if (form != 36u || value.d >= gParams.n_tokens) return false;
            tag = type_expr_ref_tag[value.d]; payload = type_expr_ref_payload[value.d];
            break;
        }
        if (core.kind == 19u)
        {
            tag = call_inference_result_tag[root];
            payload = call_inference_result_payload[root];
            if (tag == 0u)
            {
                uint instance = call_result_instance[root];
#if defined(INFERENCE_DEFERRED_CLOSURE)
                // The includer requires this row to be closed (its canonical
                // ID read at the includer's one ID site), as if this check
                // had failed otherwise.
                inference_deferred_closure = instance;
#else
                if (!INFERENCE_CALL_RESULT_CLOSED(instance)) return false;
#endif
                tag = 3u; payload = instance;
            }
        }
        else if (core.kind == 24u)
        {
            tag = call_inference_result_tag[root];
            payload = call_inference_result_payload[root];
        }
        else if (core.kind == 21u)
        {
            if (value.c >= gParams.n_tokens) return false;
            tag = member_result_ref_tag[value.c]; payload = member_result_ref_payload[value.c];
        }
        else if (core.kind == 22u || core.kind == 33u)
        {
            // Qualified value resolution owns the path head. payload.d is a
            // name-expression token and is not the path's ownership contract.
            uint token = core.kind == 33u ? core.token_start
                : value.d < gParams.n_tokens ? value.d : core.token_start;
            if (token >= gParams.n_tokens) return false;
            named_expression_reference(token, tag, payload);
        }
        else if (core.kind == 28u)
        {
            tag = semantic_expr_ref_tag_by_hir[root];
            payload = semantic_expr_ref_payload_by_hir[root];
        }
        else if (core.kind == 34u || core.kind == 36u)
        {
            // A match publishes at its `match` token, `value?` at its `?`.
            uint token = core.kind == 34u ? core.token_start : core.token_end - 1u;
            if (token >= gParams.n_tokens) return false;
            if (!current_match)
            {
                tag = call_inference_result_tag[root]; payload = call_inference_result_payload[root];
            }
            else
            {
                tag = decl_type_ref_tag[token]; payload = decl_type_ref_payload[token];
            }
        }
        else if (core.kind == 23u)
        {
            tag = 1u; payload = hir_scalar_type_for_hir(core.kind, value.a);
            uint context = literal_context_type_by_hir[root];
            if ((value.a == HIR_SEM_EXPR_INT && scalar_is_integer(context)) ||
                (value.a == HIR_SEM_EXPR_FLOAT && scalar_is_float(context)))
                payload = context;
        }
        else return false;
        break;
    }
#ifdef INFERENCE_INDEX_GRAPH
    // The including kernel reads the type rows through its own graph.
    if (!checked_index_elements<INFERENCE_INDEX_GRAPH>(indices, INFERENCE_TYPE_CAPACITY(), tag, payload))
        return false;
#else
    if (!checked_index_elements(indices, type_instance_kind, type_instance_elem_ref_tag,
        type_instance_elem_ref_payload, tag, payload)) return false;
#endif
    return (tag == 1u && payload != 0u && payload != INVALID_REF) ||
        (tag == 2u && payload < gParams.n_tokens && type_generic_param_slot_by_token[payload] != INVALID_REF) ||
        (tag == 3u && payload < INFERENCE_TYPE_CAPACITY() && type_instance_kind[payload] != 0u);
}
