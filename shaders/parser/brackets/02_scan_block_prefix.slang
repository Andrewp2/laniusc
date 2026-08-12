// Finalizes the hierarchical scan of bracket block summaries.

struct Params
{
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> block_sum;
StructuredBuffer<int> block_maxdepth;
StructuredBuffer<int> prefix_sum;
StructuredBuffer<int> prefix_min;
RWStructuredBuffer<int> block_prefix;
RWStructuredBuffer<int> out_depths;
RWStructuredBuffer<uint> out_valid;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    const uint B = gParams.n_blocks;
    if (tid.x >= B)
        return;

    int exclusive_sum = prefix_sum[tid.x] - block_sum[tid.x];
    block_prefix[tid.x] = exclusive_sum;

    // Every active thread writes the same aggregate result; this keeps the
    // finalization free of a single fixed-lane owner.
    int final_depth = prefix_sum[B - 1u];
    int min_depth = prefix_min[B - 1u];
    out_depths[0] = final_depth;
    out_depths[1] = min_depth;
    int layer_offset = min_depth < 0 ? -min_depth : 0;
    InterlockedMax(out_depths[2], exclusive_sum + block_maxdepth[tid.x] + layer_offset);
    out_valid[0] = (min_depth >= 0 && final_depth == 0) ? 1u : 0u;
}
