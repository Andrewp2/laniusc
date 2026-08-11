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
StructuredBuffer<uint> expr_result_root;
StructuredBuffer<uint> arm_owner_match;
StructuredBuffer<uint> arm_pattern;
StructuredBuffer<uint> arm_result;
StructuredBuffer<uint> arm_ordinal;
RWStructuredBuffer<uint> raw_to_arm;
RWStructuredBuffer<uint> payload_start;
RWStructuredBuffer<uint> payload_count;
RWStructuredBuffer<uint> match_arm_range_words;
RWStructuredBuffer<uint> match_pattern_to_arm;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirMatchArm> hir_match_arms;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
}
uint mapped_expression(uint raw)
{
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint root = expr_result_root[raw];
    uint dense = mapped(root);
    return dense != INVALID ? dense : mapped(raw);
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
    HirMatchArm arm;
    arm.owner = mapped(arm_owner_match[raw]);
    arm.pattern = mapped(arm_pattern[raw]);
    arm.result = mapped_expression(arm_result[raw]);
    arm.ordinal = arm_ordinal[raw];
    hir_match_arms[row] = arm;
    uint arm_node = mapped(raw);
    if (arm_node < gCanonical.canonical_capacity)
        match_pattern_to_arm[arm_node] = row;
    if (arm.pattern < gCanonical.canonical_capacity)
        match_pattern_to_arm[arm.pattern] = row;
    raw_to_arm[raw] = row;
    payload_start[row] = INVALID;
    payload_count[row] = 0u;
    if (arm.owner < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(match_arm_range_words[arm.owner * 2u], row, ignored);
        InterlockedAdd(match_arm_range_words[arm.owner * 2u + 1u], 1u, ignored);
    }
}
