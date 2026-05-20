// x86_64 owning-function block-prefix scan.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_func_owner_scan_block_sum;
StructuredBuffer<uint> x86_func_owner_scan_block_prefix_in;

RWStructuredBuffer<uint> x86_func_owner_scan_block_prefix_out;

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

    x86_func_owner_scan_block_prefix_out[i] =
        block_prefix_scan_step<uint, PrefixScanU32Max>(
            i,
            gScan.scan_step,
            x86_func_owner_scan_block_sum,
            x86_func_owner_scan_block_prefix_in);
}
