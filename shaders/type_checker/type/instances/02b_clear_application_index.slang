// Rebuild structural keys after a checked body environment changes source
// argument rows. Generated type rows remain stable and retain their identities.
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
    uint capacity; uint stride;
    type_instance_lookup_head.GetDimensions(capacity, stride);
    for (uint row = lane; row < capacity; row += gParams.n_tokens)
        type_instance_lookup_head[row] = 0u;
    type_instance_lookup_next.GetDimensions(capacity, stride);
    for (uint row = lane; row < capacity; row += gParams.n_tokens)
    {
        type_instance_lookup_next[row] = 0u;
        type_instance_lookup_present[row] = 0u;
    }
    // Rebuilding lookup buckets does not invalidate checked member references.
    // Their page producers refresh each instance under its current environment;
    // only the compilation workspace clear resets their storage and ownership.
}
