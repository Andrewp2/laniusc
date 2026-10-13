// Validate every element against the complete literal type after inference
// converges. Work is parallel per element, including arbitrarily large arrays.
#include "array_literal_inference_inputs.slang"
import status;
import type_checker.checked_array_counts;
StructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (call_inference_state[0u] != 0u) return;
    uint row = dtid.x + dtid.y * 16776960u;
    if (valid_hir(row) && compact_hir_core[row].kind == HIR_ARRAY_EXPR)
    {
        uint actual = call_inference_result_payload[row];
        uint expected = expected_array_literal_instance(row);
        uint expected_count = 0u;
        bool closed_expected = valid_instance(expected) &&
            checked_source_array_count(type_instance_len_kind[expected],
                type_instance_len_payload[expected], gParams.n_tokens, expected_count);
        if (call_inference_result_tag[row] != TYPE_REF_INSTANCE || !valid_instance(actual) ||
            type_instance_kind[actual] != TYPE_INSTANCE_ARRAY ||
            !checked_source_array_length_matches_count(type_instance_len_kind[actual],
                type_instance_len_payload[actual], compact_array_element_count[row], gParams.n_tokens) ||
            (valid_instance(expected) && !checked_source_array_length_valid(type_instance_len_kind[expected],
                type_instance_len_payload[expected], gParams.n_tokens)) ||
            (closed_expected && expected_count != compact_array_element_count[row]))
            record_min_token_error(status, compact_hir_core[row].token_start, 3u, 0u);
    }
    if (row >= min(compact_array_element_row_count[0u], gParams.n_hir_nodes)) return;
    HirArrayElement element = compact_array_elements[row];
    if (!valid_hir(element.array) || !valid_hir(element.value)) return;
    uint instance = call_inference_result_payload[element.array];
    if (call_inference_result_tag[element.array] != TYPE_REF_INSTANCE || !valid_instance(instance)) return;
    uint tag; uint payload;
    if (!inference_value_reference(element.value, tag, payload) ||
        !scoped_type_refs_equal<ScopedCheckedTypeGraph>(
            type_instance_elem_ref_tag[instance], type_instance_elem_ref_payload[instance], INVALID,
            tag, payload, INVALID, checked_type_capacity(), gParams.n_tokens))
        record_min_token_error(status, compact_hir_core[element.value].token_start, 3u, 0u);
}
