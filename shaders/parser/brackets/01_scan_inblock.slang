// shaders/parser/brackets_01_scan_inblock.slang
// Per-workgroup exclusive scan of +1/-1 deltas. Writes in-block exscan and block summaries.

import gpu_index;
import prefix_scan;

struct Params
{
    uint n_sc;
    uint wg_size;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;             // len = n_sc (odd=push, even=pop)
StructuredBuffer<uint> partial_parse_status;  // [4]=actual stack-change count
RWStructuredBuffer<int> exscan_inblock; // len = n_sc (exclusive prefix inside block)
RWStructuredBuffer<int> block_sum;      // len = n_blocks
RWStructuredBuffer<int> block_minpref;  // len = n_blocks (min prefix within block)
RWStructuredBuffer<int> block_maxdepth; // len = n_blocks (max depth within block)

groupshared int s_val[256];
groupshared int2 s_min_max[256];

static const uint MAX_GROUPS_X = 65535u;

// x: running minimum, y: running maximum.
public struct BracketScanI32x2MinMax : IPrefixScanOp<int2>
{
    public static int2 identity()
    {
        return int2(2147483647, -2147483647);
    }

    public static int2 combine(int2 left, int2 right)
    {
        return int2(min(left.x, right.x), max(left.y, right.y));
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID,
          uint3 ltid: SV_GroupThreadID,
          uint3 gid: SV_GroupID)
{
    const uint n = min(gParams.n_sc, partial_parse_status[4u]);
    const uint GSIZE = gParams.wg_size; // 256
    const uint block = linear_group_id_2d(gid, MAX_GROUPS_X);
    const uint base = block * GSIZE;
    const uint i = base + ltid.x;

    // Load +1/-1 and build inclusive scan in shared memory
    int v = 0;
    if (i < n)
    {
        uint code = sc_stream[i];
        v = ((code & 1u) == 1u) ? 1 : -1;
    }
    int inc = prefix_scan_i32_256(ltid.x, v);
    s_val[ltid.x] = inc;
    GroupMemoryBarrierWithGroupSync();
    int block_total = s_val[GSIZE - 1u];
    int inclusive_depth = s_val[ltid.x];

    // Convert to exclusive scan (ex = inc - val)
    int ex = inc - v;

    // One scan gives the block-local minimum of the exclusive prefixes
    // (clamped to 0) and a cheap upper bound on the block's maximum depth;
    // block_prefix is added later.
    int2 min_max = prefix_scan_inclusive<int2, BracketScanI32x2MinMax, 256>(
        ltid.x,
        int2(min(ex, 0), max(ex + ((inclusive_depth > 0) ? 1 : 0), ex)),
        s_min_max);

    if (i < n)
    {
        exscan_inblock[i] = ex;
    }
    if (ltid.x + 1u == GSIZE)
    {
        block_sum[block] = block_total;
        block_minpref[block] = min_max.x;
        block_maxdepth[block] = min_max.y;
    }
}
