// Exclusive scan of delimiter depths and token-context events, in one
// workgroup.
//
// Blocks are scanned in tiles of 256, in order: depths are summed and
// events take their maximum, each from the tiles before.

import prefix_scan;

struct Params
{
    uint n_blocks;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

struct PrefixScanI32x4Add : IPrefixScanOp<int4>
{
    static int4 identity()
    {
        return int4(0, 0, 0, 0);
    }

    static int4 combine(int4 left, int4 right)
    {
        return left + right;
    }
};

struct PrefixScanU32x2Max : IPrefixScanOp<uint2>
{
    static uint2 identity()
    {
        return uint2(0u, 0u);
    }

    static uint2 combine(uint2 left, uint2 right)
    {
        return max(left, right);
    }
};

ConstantBuffer<Params> gDelimiterScan;
StructuredBuffer<int> block_sum_brace;
StructuredBuffer<int> block_sum_bracket;
StructuredBuffer<int> block_sum_paren;
StructuredBuffer<int> block_sum_angle;
StructuredBuffer<uint> top_brace_owner_block;
StructuredBuffer<uint> statement_event_block;

RWStructuredBuffer<int> block_prefix_brace;
RWStructuredBuffer<int> block_prefix_bracket;
RWStructuredBuffer<int> block_prefix_paren;
RWStructuredBuffer<int> block_prefix_angle;
RWStructuredBuffer<uint> top_brace_owner_block_prefix;
RWStructuredBuffer<uint> statement_event_block_prefix;

static const uint WG_SIZE = 256u;
groupshared int4 depth_scan_values[256];
groupshared uint2 event_scan_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x != 0u || gid.y != 0u)
        return;
    uint lane = ltid.x;
    uint n_blocks = gDelimiterScan.n_blocks;
    int4 depth_carry = int4(0, 0, 0, 0);
    uint2 event_carry = uint2(0u, 0u);
    for (uint tile = 0u; tile < n_blocks; tile += WG_SIZE)
    {
        uint i = tile + lane;
        int4 depth = int4(0, 0, 0, 0);
        uint2 event = uint2(0u, 0u);
        if (i < n_blocks)
        {
            depth = int4(
                block_sum_brace[i], block_sum_bracket[i],
                block_sum_paren[i], block_sum_angle[i]);
            event = uint2(top_brace_owner_block[i], statement_event_block[i]);
        }
        prefix_scan_inclusive<int4, PrefixScanI32x4Add, 256>(lane, depth, depth_scan_values);
        prefix_scan_inclusive<uint2, PrefixScanU32x2Max, 256>(lane, event, event_scan_values);
        int4 exclusive_depth = depth_carry
            + (lane == 0u ? int4(0, 0, 0, 0) : depth_scan_values[lane - 1u]);
        uint2 exclusive_event = max(
            event_carry,
            lane == 0u ? uint2(0u, 0u) : event_scan_values[lane - 1u]);
        if (i < n_blocks)
        {
            block_prefix_brace[i] = exclusive_depth.x;
            block_prefix_bracket[i] = exclusive_depth.y;
            block_prefix_paren[i] = exclusive_depth.z;
            block_prefix_angle[i] = exclusive_depth.w;
            top_brace_owner_block_prefix[i] = exclusive_event.x;
            statement_event_block_prefix[i] = exclusive_event.y;
        }
        depth_carry += depth_scan_values[WG_SIZE - 1u];
        event_carry = max(event_carry, event_scan_values[WG_SIZE - 1u]);
        GroupMemoryBarrierWithGroupSync();
    }
}
