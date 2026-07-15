// In-place local scan of the bucket-major histogram.

import prefix_scan;

struct ScanParams { uint n_items; uint n_blocks; uint scan_step; uint out_capacity; };
ConstantBuffer<ScanParams> gScan;
RWStructuredBuffer<uint> expr_radix_histogram;
RWStructuredBuffer<uint> expr_radix_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    if (block >= gScan.n_blocks)
        return;
    uint lane = ltid.x;
    uint i = block * WG_SIZE + lane;
    uint value = i < gScan.n_items ? expr_radix_histogram[i] : 0u;
    uint inclusive = prefix_scan_u32_256(lane, value);
    if (i < gScan.n_items)
        expr_radix_histogram[i] = inclusive - value;
    if (lane == WG_SIZE - 1u)
        expr_radix_block_sum[block] = inclusive;
}
