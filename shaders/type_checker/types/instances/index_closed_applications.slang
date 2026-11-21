// Publish collision-safe buckets for the immutable checked applications.
// Generated applications will use the same structural key and bucket relation.
// A row's present word is its bucket plus one, so clearing the index
// (clear_type_application_index) visits only the job's live rows.
//
// The inference rounds' passes visit the listed live rows
// (live_type_row_list.slang), the others every live row
// (live_type_rows.slang). One kernel serves both: new kernels may keep no
// per-thread arrays, and the structural hash keeps one.
import type_checker.checked_types.checked_type_graph;
import type_checker.scoped_types.scoped_type_hash;
#include "live_type_row_list.slang"

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
// `listed`: 1 for the passes of the inference rounds.
struct TypeRowListParams { uint listed; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<TypeRowListParams> gTypeRowList;
RWStructuredBuffer<uint> type_instance_lookup_head;
RWStructuredBuffer<uint> type_instance_lookup_next;
RWStructuredBuffer<uint> type_instance_lookup_present;
StructuredBuffer<uint> type_application_count;
StructuredBuffer<uint> token_count;

void index_closed_application(uint instance, uint buckets, uint capacity)
{
    if (type_instance_lookup_present[instance] != 0u || type_instance_kind[instance] == 0u) return;
    uint hash;
    if (!scoped_type_ref_hash<ScopedCheckedTypeGraph>(3u, instance, 0xffffffffu,
        capacity, gParams.n_tokens, hash)) return;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    bool listed = gTypeRowList.listed != 0u;
    ListedTypeRows rows = listed_type_rows();
    uint lanes = listed ? rows.lanes : live_type_row_lanes(gParams.n_tokens, token_count[0u]);
    if (lane >= lanes) return;
    uint buckets; uint stride;
    type_instance_lookup_head.GetDimensions(buckets, stride);
    uint capacity = checked_type_capacity();
    uint source_rows;
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    uint generated = type_application_count[0u];
    uint live = listed ? listed_type_row_count(rows, source_rows, capacity, generated)
        : live_type_row_count(gParams.n_tokens, source_rows, capacity, generated);
    for (uint index = lane; index < live; index += lanes)
    {
        uint instance = listed ? listed_type_row(rows, index, source_rows)
            : live_type_row(index, gParams.n_tokens, source_rows);
        index_closed_application(instance, buckets, capacity);
    }
}
