// One-workgroup scan of compact per-block sums for two counted scans.

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
StructuredBuffer<uint> scan_block_sum_left;
StructuredBuffer<uint> scan_block_sum_right;
RWStructuredBuffer<uint> scan_block_prefix_left;
RWStructuredBuffer<uint> scan_block_prefix_right;

static const uint WG_SIZE = 256u;
groupshared uint2 block_scan_tile_total;

uint active_blocks()
{
    uint items = min(scan_count[0], gHierarchy.n_items);
    return (items + WG_SIZE - 1u) / WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint blocks = active_blocks();
    uint2 carry = uint2(0u, 0u);
    for (uint base = 0u; base < blocks; base += WG_SIZE)
    {
        uint i = base + ltid.x;
        uint2 value = i < blocks
            ? uint2(scan_block_sum_left[i], scan_block_sum_right[i])
            : uint2(0u, 0u);
        uint2 inclusive = prefix_scan_u32x2_256(ltid.x, value);
        if (i < blocks)
        {
            uint2 prefix = carry + inclusive;
            scan_block_prefix_left[i] = prefix.x;
            scan_block_prefix_right[i] = prefix.y;
        }

        if (ltid.x == WG_SIZE - 1u)
            block_scan_tile_total = inclusive;
        GroupMemoryBarrierWithGroupSync();
        carry += block_scan_tile_total;
    }
}
