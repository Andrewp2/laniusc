// shaders/parser/brackets_02_scan_block_prefix.slang
// Scan block sums → block_prefix, compute final_depth and global min_depth.

struct Params
{
    uint n_blocks;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> block_sum;      // len = n_blocks
StructuredBuffer<int> block_minpref;  // len = n_blocks
RWStructuredBuffer<int> block_prefix; // len = n_blocks (exclusive)
RWStructuredBuffer<int> out_depths;   // [0]=final, [1]=min
RWStructuredBuffer<uint> out_valid;   // set to 1 here; later kernels AND in errors

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    const uint B = gParams.n_blocks;
    if (tid.x >= B)
        return;

    // Simple sequential prefix at block granularity via single-dispatch grid (B <= 65536 typical).
    // (If you expect B >> 1e5, mirror the lexer’s 01/02/03 pattern here.)
    int prefix = 0;
    for (uint b = 0; b < tid.x; ++b)
        prefix += block_sum[b];
    block_prefix[tid.x] = prefix;

    GroupMemoryBarrierWithGroupSync();

    // Thread 0 computes final/min
    if (tid.x == 0)
    {
        int final_depth = 0;
        int min_depth = 0;
        int run = 0;
        for (uint b = 0; b < B; ++b)
        {
            // min over (prefix_before_block + block_minpref[b])
            int cand = run + block_minpref[b];
            if (cand < min_depth)
                min_depth = cand;
            run += block_sum[b];
        }
        final_depth = run;
        out_depths[0] = final_depth;
        out_depths[1] = min_depth;
        out_valid[0] = (min_depth >= 0 && final_depth == 0) ? 1u : 0u;
    }
}
