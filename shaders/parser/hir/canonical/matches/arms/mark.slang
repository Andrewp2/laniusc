import generated_parse_production_ids;
import token_features;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_feature_flags;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> arm_owner_match;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> candidate_raw_by_anchor;
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
    if (!parser_feature_enabled(token_feature_flags, PARSER_FEATURE_MATCHES))
        return;
    if (raw >= active_count() || node_kind[raw] != PROD_MATCH_ARM ||
        arm_owner_match[raw] == INVALID) return;
    uint anchor = hir_token_pos[raw];
    if (anchor >= gCanonical.canonical_capacity) return;
    uint ignored;
    InterlockedMax(candidate_raw_by_anchor[anchor], raw + 1u, ignored);
    InterlockedMax(family_flag[anchor], 1u, ignored);
}
