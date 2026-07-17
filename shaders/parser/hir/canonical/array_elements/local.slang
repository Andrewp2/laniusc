import prefix_scan;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
RWStructuredBuffer<uint> family_local_prefix;
RWStructuredBuffer<uint> family_block_sum;
static const uint MAX_GROUPS_X = 65535u;
uint group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = group_id(gid), lane = ltid.x, raw = block * 256u + lane;
    uint flag = raw < gCanonical.raw_capacity ? family_flag[raw] : 0u;
    uint inclusive = prefix_scan_u32_256(lane, flag);
    if (raw < gCanonical.raw_capacity) family_local_prefix[raw] = inclusive - flag;
    if (lane == 255u) family_block_sum[block] = inclusive;
}
