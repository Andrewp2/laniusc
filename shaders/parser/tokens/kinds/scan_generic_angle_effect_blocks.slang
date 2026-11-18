// Exclusive scan of contextual-`>>` stack-effect summaries, in one
// workgroup.
//
// Blocks are scanned in tiles of 256, in order. A tile's prefixes combine
// the summary of every tile before it with the tile's own exclusive scan,
// whose first lane starts from (0, 0).

import prefix_scan;

struct Params
{
    uint n_blocks;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gGenericScan;
StructuredBuffer<int> block_sum;
StructuredBuffer<int> block_min;
RWStructuredBuffer<int> block_prefix_sum;
RWStructuredBuffer<int> block_prefix_min;

static const uint WG_SIZE = 256u;
groupshared int2 scan_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x != 0u || gid.y != 0u)
        return;
    uint lane = ltid.x;
    uint n_blocks = gGenericScan.n_blocks;
    int2 carry = int2(0, 0);
    for (uint tile = 0u; tile < n_blocks; tile += WG_SIZE)
    {
        uint i = tile + lane;
        int2 value = i < n_blocks ? int2(block_sum[i], block_min[i]) : int2(0, 0);
        prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(lane, value, scan_values);
        int2 exclusive = lane == 0u ? int2(0, 0) : scan_values[lane - 1u];
        int2 total = scan_values[WG_SIZE - 1u];
        if (tile != 0u)
            exclusive = PrefixScanI32x2SumMinPrefix.combine(carry, exclusive);
        if (i < n_blocks)
        {
            block_prefix_sum[i] = exclusive.x;
            block_prefix_min[i] = exclusive.y;
        }
        carry = tile == 0u ? total : PrefixScanI32x2SumMinPrefix.combine(carry, total);
        GroupMemoryBarrierWithGroupSync();
    }
}
