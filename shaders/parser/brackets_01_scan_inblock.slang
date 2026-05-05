// shaders/parser/brackets_01_scan_inblock.slang
// Per-workgroup exclusive scan of +1/-1 deltas. Writes in-block exscan and block summaries.

import prefix_scan;

struct Params
{
    uint n_sc;
    uint wg_size;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;       // len = n_sc (odd=push, even=pop)
RWStructuredBuffer<int> exscan_inblock; // len = n_sc (exclusive prefix inside block)
RWStructuredBuffer<int> block_sum;      // len = n_blocks
RWStructuredBuffer<int> block_minpref;  // len = n_blocks (min prefix within block)
RWStructuredBuffer<int> block_maxdepth; // len = n_blocks (max depth within block)

groupshared int s_val[256];
groupshared int s_minp[256];
groupshared int s_depth[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID,
          uint3 ltid: SV_GroupThreadID,
          uint3 gid: SV_GroupID)
{
    const uint n = gParams.n_sc;
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
    s_minp[ltid.x] = min(ex, 0);
    s_depth[ltid.x] = max(ex + ((s_val[ltid.x] > 0) ? 1 : 0), ex); // cheap upper bound proxy for max depth

    GroupMemoryBarrierWithGroupSync();

    // Reduce min and max
    for (uint step = GSIZE >> 1; step > 0; step >>= 1)
    {
        if (ltid.x < step)
        {
            s_minp[ltid.x] = min(s_minp[ltid.x], s_minp[ltid.x + step]);
            s_depth[ltid.x] = max(s_depth[ltid.x], s_depth[ltid.x + step]);
        }
        GroupMemoryBarrierWithGroupSync();
    }

    if (i < n)
    {
        exscan_inblock[i] = ex;
    }
    if (ltid.x == 0)
    {
        int sum = s_val[GSIZE - 1];
        block_sum[gid.x] = sum;
        block_minpref[gid.x] = s_minp[0];
        block_maxdepth[gid.x] = s_depth[0];
    }
}
