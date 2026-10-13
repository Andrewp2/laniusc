// Publish collision-safe buckets for the immutable checked applications.
// Generated applications will use the same structural key and bucket relation.
import type_checker.checked_type_graph;
import type_checker.scoped_type_hash;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> type_instance_lookup_head;
RWStructuredBuffer<uint> type_instance_lookup_next;
RWStructuredBuffer<uint> type_instance_lookup_present;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    if (lane >= gParams.n_tokens) return;
    uint buckets; uint stride;
    type_instance_lookup_head.GetDimensions(buckets, stride);
    uint capacity = checked_type_capacity();
    for (uint instance = lane; instance < capacity; instance += gParams.n_tokens)
    {
        if (type_instance_lookup_present[instance] != 0u) continue;
        uint hash;
        if (!scoped_type_ref_hash<ScopedCheckedTypeGraph>(3u, instance, 0xffffffffu,
            capacity, gParams.n_tokens, hash)) continue;
        // Slang 2026.2 drops the output of the three-argument exchange on
        // SPIR-V. Compare/exchange publishes the same linked bucket and keeps
        // every returned predecessor defined on the supported toolchain.
        uint expected = 0u;
        for (;;)
        {
            uint previous;
            InterlockedCompareExchange(type_instance_lookup_head[hash % buckets],
                expected, instance + 1u, previous);
            if (previous == expected) break;
            expected = previous;
        }
        type_instance_lookup_next[instance] = expected;
        type_instance_lookup_present[instance] = 1u;
    }
}
