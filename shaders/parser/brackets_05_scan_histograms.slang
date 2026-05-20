// shaders/parser/brackets_05_scan_histograms.slang
// Exclusive scan hist_push / hist_pop → off_push / off_pop; also detect count mismatch.

import atomics;
import prefix_scan;

struct Params
{
    uint n_layers;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hist_push;
StructuredBuffer<uint> hist_pop;
StructuredBuffer<uint> prefix_push_in;
StructuredBuffer<uint> prefix_pop_in;
RWStructuredBuffer<uint> prefix_push_out;
RWStructuredBuffer<uint> prefix_pop_out;
RWStructuredBuffer<uint> out_valid; // AND with (hist_push==hist_pop) over all layers

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint L = gParams.n_layers;
    if (tid.x >= L)
        return;

    uint push_seed;
    uint pop_seed;
    if (gParams.scan_step == 0u)
    {
        push_seed = tid.x == 0u ? 0u : hist_push[tid.x - 1u];
        pop_seed = tid.x == 0u ? 0u : hist_pop[tid.x - 1u];

        // Count mismatch makes the stream invalid (but we can still produce partial matches).
        if (hist_push[tid.x] != hist_pop[tid.x])
            atomic_u32_and(out_valid, 0u, 0u);
    }
    else
    {
        push_seed = 0u;
        pop_seed = 0u;
    }

    prefix_push_out[tid.x] = parallel_scan_step_value<uint, PrefixScanU32Add>(
        tid.x,
        gParams.scan_step,
        push_seed,
        prefix_push_in);
    prefix_pop_out[tid.x] = parallel_scan_step_value<uint, PrefixScanU32Add>(
        tid.x,
        gParams.scan_step,
        pop_seed,
        prefix_pop_in);
}
