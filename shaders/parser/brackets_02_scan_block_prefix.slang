// shaders/parser/brackets_02_scan_block_prefix.slang
// Parallel scan of block summaries → block_prefix, final_depth, and global min_depth.

struct Params
{
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> block_sum;          // len = n_blocks
StructuredBuffer<int> block_minpref;      // len = n_blocks
StructuredBuffer<int> prefix_sum_in;      // inclusive scanned block sums
StructuredBuffer<int> prefix_min_in;      // inclusive scanned block min-prefix summaries
RWStructuredBuffer<int> prefix_sum_out;
RWStructuredBuffer<int> prefix_min_out;
RWStructuredBuffer<int> block_prefix;     // len = n_blocks (exclusive)
RWStructuredBuffer<int> out_depths;       // [0]=final, [1]=min
RWStructuredBuffer<uint> out_valid;       // set to 1 here; later kernels AND in errors

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    const uint B = gParams.n_blocks;
    if (tid.x >= B)
        return;

    if (gParams.scan_step == 0u)
    {
        prefix_sum_out[tid.x] = block_sum[tid.x];
        prefix_min_out[tid.x] = block_minpref[tid.x];
        return;
    }

    if (gParams.scan_step < B)
    {
        int sum = prefix_sum_in[tid.x];
        int minp = prefix_min_in[tid.x];
        if (tid.x >= gParams.scan_step)
        {
            int left_sum = prefix_sum_in[tid.x - gParams.scan_step];
            int left_min = prefix_min_in[tid.x - gParams.scan_step];
            minp = min(left_min, left_sum + minp);
            sum = left_sum + sum;
        }
        prefix_sum_out[tid.x] = sum;
        prefix_min_out[tid.x] = minp;
        return;
    }

    block_prefix[tid.x] = tid.x == 0u ? 0 : prefix_sum_in[tid.x - 1u];

    // Every active thread writes the same aggregate result; this keeps the
    // finalization free of a single fixed-lane owner.
    int final_depth = prefix_sum_in[B - 1u];
    int min_depth = prefix_min_in[B - 1u];
    out_depths[0] = final_depth;
    out_depths[1] = min_depth;
    out_valid[0] = (min_depth >= 0 && final_depth == 0) ? 1u : 0u;
}
