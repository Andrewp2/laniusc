// Rebuild structural keys after a checked body environment changes source
// argument rows. Generated type rows remain stable and retain their identities.
//
// Only the job's live rows were indexed (02c_index_closed_applications), and
// each indexed row's present word is its bucket plus one: clearing those
// buckets and rows clears the whole index that type_instances.clear zeroed.
#include "live_type_rows.slang"
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> type_instance_lookup_head;
RWStructuredBuffer<uint> type_instance_lookup_next;
RWStructuredBuffer<uint> type_instance_lookup_present;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_application_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    if (lane >= gParams.n_tokens) return;
    uint buckets; uint rows; uint source_rows; uint stride;
    type_instance_lookup_head.GetDimensions(buckets, stride);
    type_instance_lookup_next.GetDimensions(rows, stride);
    type_generic_param_slot_by_token.GetDimensions(source_rows, stride);
    // The index has one next and present word per type row.
    uint live = live_type_row_count(gParams.n_tokens, source_rows, rows, type_application_count[0u]);
    for (uint index = lane; index < live; index += gParams.n_tokens)
    {
        uint row = live_type_row(index, gParams.n_tokens, source_rows);
        uint bucket = type_instance_lookup_present[row];
        if (bucket != 0u && bucket <= buckets) type_instance_lookup_head[bucket - 1u] = 0u;
        type_instance_lookup_next[row] = 0u;
        type_instance_lookup_present[row] = 0u;
    }
    // Rebuilding lookup buckets does not invalidate checked member references.
    // Their page producers refresh each instance under its current environment;
    // only the compilation workspace clear resets their storage and ownership.
}
