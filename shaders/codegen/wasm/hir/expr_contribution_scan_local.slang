// Workgroup-local exclusive scan of expression byte/error contributions.

import prefix_scan;

struct ScanParams { uint n_items; uint n_blocks; uint scan_step; uint out_capacity; };
ConstantBuffer<ScanParams> gScan;
StructuredBuffer<uint4> expr_contribution;
RWStructuredBuffer<uint4> expr_contribution_local_prefix;
RWStructuredBuffer<uint4> expr_contribution_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint4 contribution_scan[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    if (block >= gScan.n_blocks)
        return;
    uint lane = ltid.x;
    uint i = block * WG_SIZE + lane;
    uint4 value = i < gScan.n_items ? expr_contribution[i] : uint4(0u, 0u, 0u, 0u);
    uint4 inclusive = prefix_scan_inclusive<uint4, PrefixScanU32x4Add, 256>(
        lane, value, contribution_scan);
    if (i < gScan.n_items)
        expr_contribution_local_prefix[i] = inclusive - value;
    if (lane == WG_SIZE - 1u)
        expr_contribution_block_sum[block] = inclusive;
}
