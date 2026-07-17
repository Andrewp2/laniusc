import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> expr_result_root;
StructuredBuffer<uint> arm_owner_match;
StructuredBuffer<uint> arm_pattern;
StructuredBuffer<uint> arm_result;
StructuredBuffer<uint> arm_ordinal;
RWStructuredBuffer<uint> raw_to_arm;
RWStructuredBuffer<uint> payload_start;
RWStructuredBuffer<uint> payload_count;
RWStructuredBuffer<uint> hir_payload_words;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirMatchArm> hir_match_arms;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint semantic_anchor(uint raw)
{
    uint kind = hir_kind[raw];
    uint callee = hir_call_callee_node[raw];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[raw * 4u + 3u];
    return canonical_hir_anchor(kind, hir_token_pos[raw], hir_token_end[raw], open,
                                value_token, operator_token, gCanonical.canonical_capacity);
}
uint mapped(uint raw)
{
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint direct = raw_to_hir[raw];
    if (direct != INVALID) return direct;
    uint anchor = semantic_anchor(raw);
    if (anchor >= gCanonical.canonical_capacity) return INVALID;
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    return winner_plus_one == 0u ? INVALID : raw_to_hir[winner_plus_one - 1u];
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
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;
    uint block = raw / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[raw];
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
    raw_to_arm[raw] = row;
    payload_start[row] = INVALID;
    payload_count[row] = 0u;
    if (arm.owner < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(hir_payload_words[arm.owner * 4u + 1u], row, ignored);
        InterlockedAdd(hir_payload_words[arm.owner * 4u + 2u], 1u, ignored);
    }
}
