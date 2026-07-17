struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> payload_table_count;
StructuredBuffer<uint> variant_payload_start;
StructuredBuffer<uint> variant_payload_count;
RWStructuredBuffer<HirVariantPayload> hir_variant_payloads;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(payload_table_count[0u], gCanonical.canonical_capacity);
    if (row >= count) return;
    HirVariantPayload payload = hir_variant_payloads[row];
    if (payload.variant >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 2u, ignored);
        InterlockedMax(canonical_status[3u], row + 1u, ignored);
        return;
    }
    uint start = variant_payload_start[payload.variant];
    uint family_count = variant_payload_count[payload.variant];
    if (start == INVALID || row < start || row - start >= family_count)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 2u, ignored);
        InterlockedMax(canonical_status[3u], row + 1u, ignored);
        return;
    }
    payload.ordinal = row - start;
    hir_variant_payloads[row] = payload;
}
