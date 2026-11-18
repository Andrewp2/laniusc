import prefix_scan;
struct Params { uint item_count; };
ConstantBuffer<Params> gScan;
StructuredBuffer<uint> input;
RWStructuredBuffer<uint> output_prefix;
RWStructuredBuffer<uint> block_sum;
static const uint MAX_GROUPS_X = 65535u;
uint group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID) {
    uint block = group_id(gid);
    uint lane = ltid.x;
    uint raw = block * 256u + lane;
    uint flag = raw < gScan.item_count ? input[raw] : 0u;
    uint inclusive = prefix_scan_u32_256(lane, flag);
    if (raw < gScan.item_count) output_prefix[raw] = inclusive - flag;
    if (lane == 255u) block_sum[block] = inclusive;
}
