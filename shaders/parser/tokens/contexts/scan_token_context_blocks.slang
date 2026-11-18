// Exclusive max scan over token-context block events, in one workgroup.
//
// Blocks are scanned in tiles of 256, in order, each from the maximum of
// the tiles before it.

import prefix_scan;

struct Params
{
    uint n_blocks;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gContextScan;
StructuredBuffer<uint> statement_event_block;
RWStructuredBuffer<uint> statement_event_block_prefix;

static const uint WG_SIZE = 256u;
groupshared uint context_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x != 0u || gid.y != 0u)
        return;
    uint lane = ltid.x;
    uint n_blocks = gContextScan.n_blocks;
    uint carry = 0u;
    for (uint tile = 0u; tile < n_blocks; tile += WG_SIZE)
    {
        uint i = tile + lane;
        uint value = i < n_blocks ? statement_event_block[i] : 0u;
        prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(lane, value, context_values);
        uint exclusive = lane == 0u ? 0u : context_values[lane - 1u];
        if (i < n_blocks)
            statement_event_block_prefix[i] = max(carry, exclusive);
        carry = max(carry, context_values[WG_SIZE - 1u]);
        GroupMemoryBarrierWithGroupSync();
    }
}
