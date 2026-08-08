import hir_records;
import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> payload_owner_arm;
StructuredBuffer<uint> payload_ordinal;
StructuredBuffer<uint> raw_to_arm;
StructuredBuffer<uint> match_pattern_to_arm;
RWStructuredBuffer<uint> arm_payload_start;
RWStructuredBuffer<uint> arm_payload_count;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirMatchPayload> hir_match_payloads;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
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
    uint owner_raw = payload_owner_arm[raw];
    uint arm = owner_raw < gCanonical.raw_capacity ? raw_to_arm[owner_raw] : INVALID;
    if (arm == INVALID)
    {
        uint owner_pattern = mapped(owner_raw);
        arm = owner_pattern < gCanonical.canonical_capacity
            ? match_pattern_to_arm[owner_pattern]
            : INVALID;
    }
    HirMatchPayload payload;
    payload.arm = arm;
    payload.pattern = mapped(raw);
    payload.ordinal = payload_ordinal[raw];
    payload.file_id = hir_token_file_id[raw];
    hir_match_payloads[row] = payload;
    if (arm < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(arm_payload_start[arm], row, ignored);
        InterlockedAdd(arm_payload_count[arm], 1u, ignored);
    }
}
