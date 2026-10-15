// Array literals publish the same checked graph consumed by all generic
// argument matchers. Elements come from an immutable preceding snapshot.
// A literal's type is the canonical array of its element type and its
// element count (the count's class, as source arrays are spelled), realized
// as a checked row; a literal whose published row already has that ID keeps
// it, since rows are unique per ID.
import hir_records;
import status;
import type_checker.mutable_checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> array_literal_element_ref_tag;
StructuredBuffer<uint> array_literal_element_ref_payload;
RWStructuredBuffer<uint> call_inference_result_tag;
RWStructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;
static const uint INVALID = 0xffffffffu;

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
    uint token = compact_hir_core[node].token_start;
    uint spare = CT_NONE;
    uint element = ct_intern_checked<CtMutableRows>(tag, payload, spare);
    // An element without a canonical ID yet waits for a later round.
    if (!ct_is_resolved(element) || ct_is_constant(element)) return;
    uint count = cc_intern_count(compact_array_element_count[node], spare);
    uint array = ct_is_resolved(count)
        ? ct_intern_small(CT_KIND_ARRAY, 2u, uint3(0u, 0u, 0u), uint2(element, count), uint2(INVALID, 0u), spare)
        : CT_UNKNOWN;
    if (!ct_is_resolved(array)) { record_min_token_error(status, token, 6u, 0x474e0001u); return; }
    uint previous = call_inference_result_payload[node];
    if (call_inference_result_tag[node] == 3u && previous < mutable_type_capacity() &&
        ct_intern_checked<CtMutableRows>(3u, previous, spare) == array) return;
    uint failure;
    uint2 operand = ct_realize(array, failure);
    uint ignored;
    // Another lane is writing a row this one needs: try again next round.
    if (failure == CT_REALIZE_BUSY) { InterlockedAdd(call_inference_state[1u], 1u, ignored); return; }
    if (operand.x != 3u)
    {
        record_min_token_error(status, token, 6u, 0x474e0000u | (failure == 0u ? CT_REALIZE_INVALID : failure));
        return;
    }
    call_inference_result_tag[node] = 3u;
    call_inference_result_payload[node] = operand.y;
    InterlockedAdd(call_inference_state[1u], 1u, ignored);
}
