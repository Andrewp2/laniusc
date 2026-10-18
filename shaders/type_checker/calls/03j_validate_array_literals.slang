// Validate every element against the complete literal type after inference
// converges. Work is parallel per element, including arbitrarily large arrays.
//
// Types compare by canonical ID (docs/canonical-type-ids.md). Literal rows
// and element results are written during inference, after the early
// canonical stage, so a lane interns what it compares on demand, from one
// site: first a literal's field scope, then an element's operands.

// A call result's closure is checked by canonical ID once it is interned.
static uint deferred_closure_row = 0xffffffffu;
bool defer_call_result_closure(uint instance)
{
    deferred_closure_row = instance;
    return true;
}
#define INFERENCE_CALL_RESULT_CLOSED(instance) defer_call_result_closure(instance)
#include "array_literal_inference_inputs.slang"
import status;
import type_checker.checked_array_counts;
import type_checker.checked_type_identity;
import type_checker.checked_slots;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_subst;
StructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

// A literal's expected array: a checked row (`row`), or a struct-literal
// field whose declared row `field` is substituted under its scope instance
// `scope` by canonical ID, `layers` array levels above the literal. A slice
// context expects no length, so it leaves `row` INVALID.
struct LiteralExpectation
{
    uint row;
    bool field;
    uint field_row;
    uint scope;
    uint root;
    uint layers;
}

// expected_literal_sequence_instance's ascent from (`root`, `layers`). It
// stops at a field context that needs a lookup; with `after_field` the first
// level resumes after that context.
LiteralExpectation ascend_literal(uint node, uint root, uint layers, bool after_field)
{
    LiteralExpectation expectation;
    expectation.row = INVALID;
    expectation.field = false;
    expectation.field_row = INVALID;
    expectation.scope = INVALID;
    expectation.root = INVALID;
    expectation.layers = 0u;
    uint expected = INVALID;
    for (uint depth = 0u; depth < 64u && valid_hir(root); depth++)
    {
        uint2 reference; uint scope;
        uint context = compact_hir_core[root].kind == HIR_ARRAY_EXPR
            ? declared_expression_context_or_field<ScopedCheckedTypeGraph>(root, checked_type_capacity(),
                after_field, reference, scope)
            : DECLARED_CONTEXT_NONE;
        after_field = false;
        if (context == DECLARED_CONTEXT_FIELD)
        {
            expectation.field = true;
            expectation.field_row = reference.y;
            expectation.scope = scope;
            expectation.root = root;
            expectation.layers = layers;
            return expectation;
        }
        expected = context == DECLARED_CONTEXT_REFERENCE && reference.x == TYPE_REF_INSTANCE
            ? reference.y : INVALID;
        if (sequence_instance(expected)) break;
        if (root != node && call_inference_result_tag[root] == TYPE_REF_INSTANCE)
        {
            expected = call_inference_result_payload[root];
            if (sequence_instance(expected)) break;
        }
        uint parent = compact_hir_core[root].parent;
        if (!valid_hir(parent) || compact_hir_core[parent].kind != HIR_ARRAY_EXPR) return expectation;
        layers++; root = parent;
    }
    for (uint i = 0u; i < layers; i++)
    {
        if (!sequence_instance(expected) ||
            type_instance_elem_ref_tag[expected] != TYPE_REF_INSTANCE) return expectation;
        expected = type_instance_elem_ref_payload[expected];
    }
    expectation.row = valid_instance(expected) && type_instance_kind[expected] == TYPE_INSTANCE_ARRAY
        ? expected : INVALID;
    return expectation;
}

// An array or slice canonical type: either gives a literal its element type.
bool canonical_sequence(uint id)
{
    return ct_kind(id) == CT_KIND_ARRAY || ct_kind(id) == CT_KIND_SLICE;
}

// The array `layers` element levels below canonical type `id`, or CT_NONE
// (also for a slice there: it expects no length).
uint descend_canonical_array(uint id, uint layers)
{
    for (uint i = 0u; i < layers; i++)
    {
        if (!canonical_sequence(id)) return CT_NONE;
        id = ct_arg(id, 0u);
        if (!ct_is_record(id)) return CT_NONE;
    }
    return ct_kind(id) == CT_KIND_ARRAY ? id : CT_NONE;
}

// Validate the literal at `row` against its expected array: checked row
// `expected`, or with `canonical` the canonical array `array`.
void validate_literal(uint row, uint expected, bool canonical, uint array)
{
    // The expected length: present, valid and, when closed, its count.
    bool present; bool length_valid; bool closed_expected; uint expected_count = 0u;
    if (canonical)
    {
        // An array's identity holds its length's count class.
        uint length = array != CT_NONE ? ct_arg(array, 1u) : CT_NONE;
        present = array != CT_NONE;
        length_valid = present && ct_is_resolved(length);
        closed_expected = present && ct_kind(length) == CC_KIND_COUNT;
        expected_count = closed_expected ? cc_count(length) : 0u;
    }
    else
    {
        present = valid_instance(expected);
        uint2 length = present ? uint2(type_instance_len_kind[expected], type_instance_len_payload[expected])
            : uint2(0u, INVALID);
        length_valid = present && checked_source_array_length_valid(length.x, length.y, gParams.n_tokens);
        closed_expected = present && checked_source_array_count(length.x, length.y, gParams.n_tokens,
            expected_count);
    }
    uint actual = call_inference_result_payload[row];
    if (call_inference_result_tag[row] != TYPE_REF_INSTANCE || !valid_instance(actual) ||
        type_instance_kind[actual] != TYPE_INSTANCE_ARRAY ||
        !checked_source_array_length_matches_count(type_instance_len_kind[actual],
            type_instance_len_payload[actual], compact_array_element_count[row], gParams.n_tokens) ||
        (present && !length_valid) ||
        (closed_expected && expected_count != compact_array_element_count[row]))
        record_min_token_error(status, compact_hir_core[row].token_start, 3u, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (call_inference_state[0u] != 0u) return;
    uint row = dtid.x + dtid.y * 16776960u;
    uint spare = CT_NONE;
    bool literal = valid_hir(row) && compact_hir_core[row].kind == HIR_ARRAY_EXPR;
    // Where a literal's ascent starts; a failed field substitution resumes
    // after the field context.
    uint ascent_root = row;
    uint ascent_layers = 0u;
    [loop]
    for (uint phase = 0u; phase < 3u; phase++)
    {
        // Phases 0 and 1: the literal at `row` (1 only to resume its ascent);
        // phase 2: the element at `row`.
        bool literal_phase = phase < 2u && literal;
        LiteralExpectation expectation;
        HirArrayElement element;
        uint2 value = uint2(0u, INVALID);
        bool value_ok = false;
        uint4 operands = uint4(0u, INVALID, 0u, INVALID);
        uint2 closure = uint2(0u, INVALID);
        if (literal_phase)
        {
            expectation = ascend_literal(row, ascent_root, ascent_layers, phase == 1u);
            if (phase == 0u && expectation.field)
                operands = uint4(TYPE_REF_INSTANCE, expectation.field_row,
                    TYPE_REF_INSTANCE, expectation.scope);
        }
        else if (phase == 2u)
        {
            if (row >= min(compact_array_element_row_count[0u], gParams.n_hir_nodes)) return;
            element = compact_array_elements[row];
            if (!valid_hir(element.array) || !valid_hir(element.value)) return;
            uint instance = call_inference_result_payload[element.array];
            if (call_inference_result_tag[element.array] != TYPE_REF_INSTANCE || !valid_instance(instance)) return;
            deferred_closure_row = INVALID;
            value_ok = inference_value_reference(element.value, value.x, value.y);
            if (value_ok)
            {
                operands = uint4(type_instance_elem_ref_tag[instance], type_instance_elem_ref_payload[instance],
                    value.x, value.y);
                if (deferred_closure_row != INVALID) closure = uint2(TYPE_REF_INSTANCE, deferred_closure_row);
            }
        }
        else continue;
        uint3 ids = uint3(CT_UNKNOWN, CT_UNKNOWN, CT_UNKNOWN);
        [loop]
        for (uint index = 0u; index < 3u; index++)
        {
            uint2 operand = index == 0u ? operands.xy : index == 1u ? operands.zw : closure;
            if (operand.x == 0u) continue;
            uint id = ct_intern_checked<CtCheckedRows>(operand.x, operand.y, spare);
            if (index == 0u) ids.x = id;
            else if (index == 1u) ids.y = id;
            else ids.z = id;
        }
        if (literal_phase)
        {
            uint array = CT_NONE;
            bool canonical = phase == 0u && expectation.field;
            if (canonical)
            {
                CtSpare substitution = ct_spare_none();
                uint substituted = ct_is_resolved(ids.x) && ct_is_record(ids.y)
                    ? ct_subst(CheckedSlots(), ids.y, ids.x, true, substitution) : CT_UNKNOWN;
                if (!canonical_sequence(substituted))
                {
                    // No substituted array or slice: resume after the field context.
                    ascent_root = expectation.root;
                    ascent_layers = expectation.layers;
                    continue;
                }
                array = descend_canonical_array(substituted, expectation.layers);
            }
            validate_literal(row, expectation.row, canonical, array);
            // Done with the literal: skip the resume phase.
            if (phase == 0u) phase = 1u;
            continue;
        }
        // A call result must be closed; the element must equal the literal's
        // element type.
        if (!value_ok || (closure.x != 0u && !ct_closed(ids.z)) ||
            !checked_types_equal_ids(CheckedSlots(), operands.x, operands.y, ids.x,
                operands.z, operands.w, ids.y, true))
            record_min_token_error(status, compact_hir_core[element.value].token_start, 3u, 0u);
    }
}
