// shaders/parser/brackets_05_scan_histograms.slang
// Exclusive scan hist_push / hist_pop → off_push / off_pop; also detect count mismatch.

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

    uint ps;
    uint pp;
    if (gParams.scan_step == 0u)
    {
        ps = tid.x == 0u ? 0u : hist_push[tid.x - 1u];
        pp = tid.x == 0u ? 0u : hist_pop[tid.x - 1u];

        // Count mismatch makes the stream invalid (but we can still produce partial matches).
        if (hist_push[tid.x] != hist_pop[tid.x])
            InterlockedAnd(out_valid[0], 0u);
    }
    else
    {
        ps = prefix_push_in[tid.x];
        pp = prefix_pop_in[tid.x];
        if (gParams.scan_step < L && tid.x >= gParams.scan_step)
        {
            ps += prefix_push_in[tid.x - gParams.scan_step];
            pp += prefix_pop_in[tid.x - gParams.scan_step];
        }
    }

    prefix_push_out[tid.x] = ps;
    prefix_pop_out[tid.x] = pp;
}
