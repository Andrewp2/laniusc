// shaders/parser/brackets_06_scatter_by_layer.slang
// Scatter indices into per-layer arrays using atomic cursors seeded from offsets.

import gpu_index;
import scatter;

struct Params
{
    uint n_sc;
    uint n_layers;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> partial_parse_status; // [4]=actual stack-change count
StructuredBuffer<uint> layer;
StructuredBuffer<uint> off_push;
StructuredBuffer<uint> off_pop;
RWStructuredBuffer<uint> cur_push;        // len = n_layers, prefilled with off_push
RWStructuredBuffer<uint> cur_pop;         // len = n_layers, prefilled with off_pop
RWStructuredBuffer<uint> pushes_by_layer; // len = n_sc (capacity)
RWStructuredBuffer<uint> pops_by_layer;   // len = n_sc (capacity)
RWStructuredBuffer<uint> slot_for_index;  // len = n_sc, absolute slot in layer array

static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(tid, MAX_GROUPS_X, WG_SIZE);
    uint n = min(gParams.n_sc, partial_parse_status[4u]);
    if (i >= n)
        return;

    // Large streams are stably ordered by the following radix passes. Seed
    // their first order buffer in source order; the small cooperative path
    // below continues to use the per-layer arrays directly.
    if (n > 2048u)
    {
        pushes_by_layer[i] = i;
        return;
    }

    uint l = layer[i];
    if (l >= gParams.n_layers)
        return;

    uint code = sc_stream[i];
    if ((code & 1u) == 1u)
    {
        uint slot = atomic_counter_add(cur_push, l, 1u);
        pushes_by_layer[slot] = i;
        slot_for_index[i] = slot;
    }
    else
    {
        uint slot = atomic_counter_add(cur_pop, l, 1u);
        pops_by_layer[slot] = i;
        slot_for_index[i] = slot;
    }
}
