import token_features;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> variant_parent_enum;
RWStructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> raw_to_variant;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    raw_to_variant[raw] = INVALID;
    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_ENUMS))
    {
        family_flag[raw] = 0u;
        return;
    }
    family_flag[raw] = raw < active_count() && variant_parent_enum[raw] != INVALID ? 1u : 0u;
}
