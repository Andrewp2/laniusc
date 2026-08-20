// One-workgroup scan of the compact per-block sums for a counted u32 scan.
//
// Source rows are scanned independently by all local workgroups. This pass
// only walks their 256-row summaries in tiles, carrying one tile total to the
// next. A bounded compilation unit therefore needs one block-prefix dispatch
// instead of an up/down dispatch hierarchy.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint level_divisor;
    uint level_offset;
    uint parent_divisor;
    uint parent_offset;
};

ConstantBuffer<Params> gHierarchy;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_block_sum;
RWStructuredBuffer<uint> scan_block_prefix;

static const uint WG_SIZE = 256u;
groupshared uint block_scan_tile_total;

uint active_blocks()
{
    uint active_items = min(scan_count[0], gHierarchy.n_items);
    return (active_items + WG_SIZE - 1u) / WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint blocks = active_blocks();
    uint carry = 0u;
    for (uint base = 0u; base < blocks; base += WG_SIZE)
    {
        uint i = base + ltid.x;
        uint value = i < blocks ? scan_block_sum[i] : 0u;
        uint inclusive = prefix_scan_u32_256(ltid.x, value);
        if (i < blocks)
            scan_block_prefix[i] = carry + inclusive;

        if (ltid.x == WG_SIZE - 1u)
            block_scan_tile_total = inclusive;
        GroupMemoryBarrierWithGroupSync();
        carry += block_scan_tile_total;
    }
}
