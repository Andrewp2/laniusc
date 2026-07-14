// Pointer-doubling scan of per-block x86 linker section totals.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint reserved;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint2> link_section_block_sum;
StructuredBuffer<uint2> link_section_block_prefix_in;
RWStructuredBuffer<uint2> link_section_block_prefix_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (block >= gScan.n_blocks)
        return;

    link_section_block_prefix_out[block] =
        block_prefix_scan_step<uint2, PrefixScanU32x2Add>(
            block,
            gScan.scan_step,
            link_section_block_sum,
            link_section_block_prefix_in);
}
