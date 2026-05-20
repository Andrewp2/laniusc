// Global prefix apply for GPU-counted u32 scans.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_local_prefix;
StructuredBuffer<uint> scan_block_prefix;
RWStructuredBuffer<uint> scan_output_prefix;
RWStructuredBuffer<uint> scan_total;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_items()
{
    return min(scan_count[0], gScan.n_items);
}

uint active_blocks()
{
    return (active_items() + WG_SIZE - 1u) / WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint blocks = active_blocks();
    if (i == 0u)
        scan_total[0] = blocks == 0u ? 0u : inclusive_scan_total(blocks, scan_block_prefix);

    if (i >= active_items())
        return;

    scan_output_prefix[i] = global_exclusive_prefix(
        i,
        WG_SIZE,
        scan_local_prefix,
        scan_block_prefix);
}
