// Snapshot first-element references before any literal publishes a new graph.
// Nonempty literals infer from their first checked element; empty literals
// require an expected array or slice type. One lane per literal, independent of its
// element count. Literal scalar context was published by a preceding dispatch.
#include "array_literal_inference_inputs.slang"
RWStructuredBuffer<uint> array_literal_element_ref_tag;
RWStructuredBuffer<uint> array_literal_element_ref_payload;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_ARRAY_EXPR) return;
    uint tag = 0u; uint payload = INVALID;
    if (compact_array_element_count[node] != 0u)
    {
        uint row = compact_array_element_start[node];
        if (row < min(compact_array_element_row_count[0u], gParams.n_hir_nodes) &&
            !inference_value_reference(compact_array_elements[row].value, tag, payload))
        { tag = 0u; payload = INVALID; }
    }
    if (tag == 0u)
    {
        uint expected = expected_literal_sequence_instance(node);
        if (valid_instance(expected))
        {
            tag = type_instance_elem_ref_tag[expected];
            payload = type_instance_elem_ref_payload[expected];
        }
    }
    array_literal_element_ref_tag[node] = tag;
    array_literal_element_ref_payload[node] = payload;
}
