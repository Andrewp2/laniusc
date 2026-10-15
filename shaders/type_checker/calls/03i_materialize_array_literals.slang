import primitive_types;
// Array literals publish the same checked graph consumed by all generic
// argument matchers. Elements come from an immutable preceding snapshot.
import hir_records;
import atomics;
import status;
import type_checker.constant_publication;
import type_checker.checked_array_counts;
import type_checker.mutable_checked_type_graph;
import type_checker.scoped_type_equality;
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> array_literal_element_ref_tag;
StructuredBuffer<uint> array_literal_element_ref_payload;
RWStructuredBuffer<uint> type_application_count;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_instance_aggregate_word_count;
RWStructuredBuffer<uint> type_native_word_count;
RWStructuredBuffer<uint> type_native_scalar_identity;
RWStructuredBuffer<uint> call_inference_result_tag;
RWStructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;
static const uint INVALID = 0xffffffffu;
#include "../type/instances/allocate_application.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    if (node >= min(compact_hir_count[0u], gParams.n_hir_nodes) ||
        compact_hir_core[node].kind != 24u) return;
    uint tag = array_literal_element_ref_tag[node];
    uint payload = array_literal_element_ref_payload[node];
    if (tag == 0u || payload == INVALID) return;
    uint length = compact_array_element_count[node];
    uint atom_row = gParams.n_hir_nodes + node;
    uint2 length_reference;
    if (atom_row < gParams.n_hir_nodes ||
        !publish_checked_constant_atom_at(atom_row, uint3(SCALAR_U32, length, 0u), length_reference))
    { record_min_token_error(status, compact_hir_core[node].token_start, 6u, 0x474e0001u); return; }
    uint previous = call_inference_result_payload[node];
    // An identical element reference is the same element type. The structural
    // comparison rejects references it cannot walk, such as an element whose
    // type name is unresolved; republishing those allocated a row and counted
    // a change every round, so inference never converged.
    if (call_inference_result_tag[node] == 3u && previous < mutable_type_capacity() &&
        type_instance_kind[previous] == 2u &&
        checked_source_array_length_matches_count(type_instance_len_kind[previous],
            type_instance_len_payload[previous], length, gParams.n_tokens) &&
        ((type_instance_elem_ref_tag[previous] == tag &&
            type_instance_elem_ref_payload[previous] == payload) ||
        scoped_type_refs_equal<MutableCheckedTypeGraph>(
            type_instance_elem_ref_tag[previous], type_instance_elem_ref_payload[previous], INVALID,
            tag, payload, INVALID, mutable_type_capacity(), gParams.n_tokens))) return;
    uint target = allocate_application(INVALID, 0u, length_reference.x, length_reference.y, INVALID, INVALID, INVALID);
    if (target == INVALID)
    { record_min_token_error(status, compact_hir_core[node].token_start, 6u, 0x474e0001u); return; }
    type_instance_elem_ref_tag[target] = tag;
    type_instance_elem_ref_payload[target] = payload;
    type_instance_kind[target] = 2u;
    call_inference_result_tag[node] = 3u;
    call_inference_result_payload[node] = target;
    uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored);
}
