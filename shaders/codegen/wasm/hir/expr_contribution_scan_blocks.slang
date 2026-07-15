// Ping-pong global prefix scan over expression contribution block sums.

import gpu_index;
import prefix_scan;

struct ScanParams { uint n_items; uint n_blocks; uint scan_step; uint out_capacity; };
ConstantBuffer<ScanParams> gScan;
StructuredBuffer<uint4> expr_contribution_block_sum;
StructuredBuffer<uint4> expr_contribution_block_prefix_in;
RWStructuredBuffer<uint4> expr_contribution_block_prefix_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (i >= gScan.n_blocks)
        return;
    expr_contribution_block_prefix_out[i] =
        block_prefix_scan_step<uint4, PrefixScanU32x4Add>(
            i,
            gScan.scan_step,
            expr_contribution_block_sum,
            expr_contribution_block_prefix_in);
}
