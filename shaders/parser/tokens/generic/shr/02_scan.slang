// Prefix the contextual-`>>` block summaries with the same stack-effect monoid.

import prefix_scan;

struct Params { uint n_tokens; uint n_blocks; uint scan_step; };
ConstantBuffer<Params> gParams;
StructuredBuffer<int> block_sum;
StructuredBuffer<int> block_min;
StructuredBuffer<int> prefix_sum_in;
StructuredBuffer<int> prefix_min_in;
RWStructuredBuffer<int> prefix_sum_out;
RWStructuredBuffer<int> prefix_min_out;
RWStructuredBuffer<int> block_prefix_sum;
RWStructuredBuffer<int> block_prefix_min;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n_blocks)
        return;
    if (gParams.scan_step == 0u)
    {
        prefix_sum_out[i] = block_sum[i];
        prefix_min_out[i] = block_min[i];
        return;
    }
    if (gParams.scan_step < gParams.n_blocks)
    {
        int2 value = block_prefix_scan_step_i32_sum_min_prefix(
            i, gParams.scan_step, block_sum, block_min, prefix_sum_in, prefix_min_in);
        prefix_sum_out[i] = value.x;
        prefix_min_out[i] = value.y;
        return;
    }
    if (i == 0u)
    {
        block_prefix_sum[i] = 0;
        block_prefix_min[i] = 0;
    }
    else
    {
        block_prefix_sum[i] = prefix_sum_in[i - 1u];
        block_prefix_min[i] = prefix_min_in[i - 1u];
    }
}
