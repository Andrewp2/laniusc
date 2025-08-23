// shaders/parser/brackets_06_scatter_by_layer.slang
// Scatter indices into per-layer arrays using atomic cursors seeded from offsets.

struct Params
{
    uint n_sc;
    uint n_layers;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> layer;
StructuredBuffer<uint> off_push;
StructuredBuffer<uint> off_pop;
RWStructuredBuffer<uint> cur_push;        // len = n_layers, prefilled with off_push
RWStructuredBuffer<uint> cur_pop;         // len = n_layers, prefilled with off_pop
RWStructuredBuffer<uint> pushes_by_layer; // len = n_sc (capacity)
RWStructuredBuffer<uint> pops_by_layer;   // len = n_sc (capacity)

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
    {
        uint slot;
        InterlockedAdd(cur_push[l], 1, slot);
        pushes_by_layer[slot] = i;
    }
    else
    {
        uint slot;
        InterlockedAdd(cur_pop[l], 1, slot);
        pops_by_layer[slot] = i;
    }
}
