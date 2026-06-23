// shaders/parser/brackets_01_scan_inblock.slang
// Per-workgroup exclusive scan of +1/-1 deltas. Writes in-block exscan and block summaries.

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
groupshared int s_minp[256];
groupshared int s_depth[256];

public struct BracketScanI32Min : IPrefixScanOp<int>
{
    public static int identity()
    {
        return 2147483647;
    }

    public static int combine(int left, int right)
    {
        return min(left, right);
    }
}

public struct BracketScanI32Max : IPrefixScanOp<int>
{
    public static int identity()
    {
        return -2147483647;
    }

    public static int combine(int left, int right)
    {
        return max(left, right);
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
    const uint base = gid.x * GSIZE;
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

    // Convert to exclusive scan (ex = inc - val) and track min-prefix / max-depth in-block
    int ex = inc - v;

    // Compute min prefix in-block: min over partial sums (exclusive domain)
    // We can reconstruct running depth within block as ex + depth_base (added later),
    // here we only need the block-local min of (ex + 0) and the block sum.
    int minp = prefix_scan_inclusive<int, BracketScanI32Min, 256>(
        ltid.x,
        min(ex, 0),
        s_minp);
    int max_depth = prefix_scan_inclusive<int, BracketScanI32Max, 256>(
        ltid.x,
        max(ex + ((s_val[ltid.x] > 0) ? 1 : 0), ex), // cheap upper bound proxy for max depth
        s_depth);

    if (i < n)
    {
        exscan_inblock[i] = ex;
    }
    if (ltid.x + 1u == GSIZE)
    {
        int sum = s_val[GSIZE - 1];
        block_sum[gid.x] = sum;
        block_minpref[gid.x] = minp;
        block_maxdepth[gid.x] = max_depth;
    }
}
