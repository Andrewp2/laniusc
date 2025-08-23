// shaders/parser/brackets_04_histogram_layers.slang
// Build histograms of pushes and pops per layer.

struct Params
{
    uint n_sc;
    uint n_layers;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> layer;       // len = n_sc
RWStructuredBuffer<uint> hist_push; // len = n_layers
RWStructuredBuffer<uint> hist_pop;  // len = n_layers

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n_sc)
        return;

    uint l = layer[i];
    if (l >= gParams.n_layers)
        return;

    uint code = sc_stream[i];
    if ((code & 1u) == 1u)
        InterlockedAdd(hist_push[l], 1);
    else
        InterlockedAdd(hist_pop[l], 1);
}
