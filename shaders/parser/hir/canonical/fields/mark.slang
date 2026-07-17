import token_features;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> decl_owner;
StructuredBuffer<uint> literal_owner;
RWStructuredBuffer<uint> family_flag;
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
    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_STRUCTS))
    {
        family_flag[raw] = 0u;
        return;
    }
    bool declaration = raw < active_count() && decl_owner[raw] != INVALID;
    bool initializer = raw < active_count() && literal_owner[raw] != INVALID;
    family_flag[raw] = declaration || initializer ? 1u : 0u;
}
