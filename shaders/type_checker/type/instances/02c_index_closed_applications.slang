// Publish collision-safe buckets for the immutable checked applications.
// Generated applications will use the same structural key and bucket relation.
// A row's present word is its bucket plus one, so clearing the index
// (02b_clear_application_index) visits only the job's live rows.
import type_checker.checked_type_graph;
import type_checker.scoped_type_hash;
#include "live_type_rows.slang"

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> type_instance_lookup_head;
RWStructuredBuffer<uint> type_instance_lookup_next;
RWStructuredBuffer<uint> type_instance_lookup_present;
StructuredBuffer<uint> type_application_count;
StructuredBuffer<uint> token_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint lanes = live_type_row_lanes(gParams.n_tokens, token_count[0u]);
    if (lane >= lanes) return;
    uint buckets; uint stride;
    type_instance_lookup_head.GetDimensions(buckets, stride);
    uint capacity = checked_type_capacity();
    uint source_rows;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    uint live = live_type_row_count(gParams.n_tokens, source_rows, capacity, type_application_count[0u]);
    for (uint index = lane; index < live; index += lanes)
    {
        uint instance = live_type_row(index, gParams.n_tokens, source_rows);
        if (type_instance_lookup_present[instance] != 0u) continue;
        uint hash;
        if (!scoped_type_ref_hash<ScopedCheckedTypeGraph>(3u, instance, 0xffffffffu,
            capacity, gParams.n_tokens, hash)) continue;
        // Slang 2026.2 drops the output of the three-argument exchange on
        // SPIR-V. Compare/exchange publishes the same linked bucket and keeps
        // every returned predecessor defined on the supported toolchain.
        uint bucket = hash % buckets;
        uint expected = 0u;
        for (;;)
        {
            uint previous;
            InterlockedCompareExchange(type_instance_lookup_head[bucket],
                expected, instance + 1u, previous);
            if (previous == expected) break;
            expected = previous;
        }
        type_instance_lookup_next[instance] = expected;
        type_instance_lookup_present[instance] = bucket + 1u;
    }
}
