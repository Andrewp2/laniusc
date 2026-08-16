import hir_records;
import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> candidate_raw_by_anchor;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> variant_parent_enum;
StructuredBuffer<uint> variant_ordinal;
RWStructuredBuffer<uint> raw_to_variant;
RWStructuredBuffer<uint> variant_payload_start;
RWStructuredBuffer<uint> variant_payload_count;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirVariant> hir_variants;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
}
uint file_for_raw(uint raw)
{
    uint token = raw < gCanonical.raw_capacity ? hir_token_pos[raw] : INVALID;
    return token < gCanonical.canonical_capacity ? token_file_id[token] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint anchor = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (anchor == 0u) family_count[0u] = total;
    if (anchor >= gCanonical.canonical_capacity || family_flag[anchor] == 0u) return;
    uint encoded = candidate_raw_by_anchor[anchor];
    uint raw = encoded == 0u ? INVALID : encoded - 1u;
    if (raw >= gCanonical.raw_capacity) return;
    uint block = anchor / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[anchor];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    HirVariant variant;
    variant.owner = mapped(variant_parent_enum[raw]);
    variant.name_token = hir_token_pos[raw];
    variant.ordinal = variant_ordinal[raw];
    variant.file_id = file_for_raw(raw);
    hir_variants[row] = variant;
    raw_to_variant[anchor] = row;
    variant_payload_start[row] = INVALID;
    variant_payload_count[row] = 0u;
}
