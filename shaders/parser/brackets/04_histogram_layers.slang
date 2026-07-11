// shaders/parser/brackets_04_histogram_layers.slang
// Build histograms of pushes and pops per layer.

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
StructuredBuffer<uint> layer;       // len = n_sc
RWStructuredBuffer<uint> hist_push; // len = n_layers
RWStructuredBuffer<uint> hist_pop;  // len = n_layers
RWStructuredBuffer<uint> match_for_index;

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

    match_for_index[i] = 0xFFFFFFFFu;

    uint l = layer[i];
    if (l >= gParams.n_layers)
        return;

    uint code = sc_stream[i];
    if ((code & 1u) == 1u)
        atomic_counter_add(hist_push, l, 1u);
    else
        atomic_counter_add(hist_pop, l, 1u);
}
