// Ping-pong block-prefix scan for WASM body fragment byte sizes.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_scan_block_sum;
StructuredBuffer<uint> body_scan_block_prefix_in;
RWStructuredBuffer<uint> body_scan_block_prefix_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gScan.n_blocks)
        return;

    body_scan_block_prefix_out[i] = block_prefix_scan_step<uint, PrefixScanU32Add>(
        i,
        gScan.scan_step,
        body_scan_block_sum,
        body_scan_block_prefix_in);
}
