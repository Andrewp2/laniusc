import prefix_scan;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
RWStructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_anchor_by_raw;
StructuredBuffer<uint> canonical_anchor_owner;
RWStructuredBuffer<uint> canonical_local_prefix;
RWStructuredBuffer<uint> canonical_block_sum;
RWStructuredBuffer<uint> canonical_status;

static const uint MAX_GROUPS_X = 65535u;
uint group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = group_id(gid);
    uint lane = ltid.x;
    uint node = block * 256u + lane;
    uint flag = 0u;
    if (node < gCanonical.raw_capacity && canonical_flag[node] != 0u)
    {
        uint anchor = canonical_anchor_by_raw[node];
        uint winner = canonical_anchor_owner[anchor] & 0x0fffffffu;
        flag = winner == node + 1u ? 1u : 0u;
        canonical_flag[node] = flag;
        if (flag != 0u)
        {
            uint ignored;
            InterlockedAdd(canonical_status[6u], 1u, ignored);
        }
    }
    uint inclusive = prefix_scan_u32_256(lane, flag);
    if (node < gCanonical.raw_capacity) canonical_local_prefix[node] = inclusive - flag;
    if (lane == 255u) canonical_block_sum[block] = inclusive;
}
