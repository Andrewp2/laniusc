// shaders/parser/brackets_05_scan_histograms.slang
// Exclusive scan hist_push / hist_pop → off_push / off_pop; also detect count mismatch.

struct Params
{
    uint n_layers;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hist_push;
StructuredBuffer<uint> hist_pop;
RWStructuredBuffer<uint> off_push;
RWStructuredBuffer<uint> off_pop;
RWStructuredBuffer<uint> out_valid; // AND with (hist_push==hist_pop) over all layers

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint L = gParams.n_layers;
    if (tid.x >= L)
        return;

    uint ps = 0;
    uint pp = 0;
    for (uint k = 0; k < tid.x; ++k)
    {
        ps += hist_push[k];
        pp += hist_pop[k];
    }
    off_push[tid.x] = ps;
    off_pop[tid.x] = pp;

    // Count mismatch makes the stream invalid (but we can still produce partial matches).
    if (hist_push[tid.x] != hist_pop[tid.x])
        InterlockedAnd(out_valid[0], 0u);
}
