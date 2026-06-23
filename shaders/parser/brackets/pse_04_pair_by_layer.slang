// shaders/parser/brackets_pse_04_pair_by_layer.slang
// PSE pairing via same-layer rank. Ranks are computed from source index order;
// atomic scatter order is not deterministic enough to define parser acceptance.

import atomics;

struct Params
{
    uint n_sc;
    uint n_layers;
    uint typed_check; // 0: ignore symbol IDs; 1: require matching symbol IDs
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hist_push;       // [n_layers]
StructuredBuffer<uint> hist_pop;        // [n_layers]
StructuredBuffer<uint> off_push;        // [n_layers]  exclusive
StructuredBuffer<uint> off_pop;         // [n_layers]  exclusive
StructuredBuffer<uint> pushes_by_layer; // [sum hist_push]
StructuredBuffer<uint> pops_by_layer;   // [sum hist_pop]
StructuredBuffer<uint> sc_stream;       // [n_sc]
StructuredBuffer<uint> partial_parse_status; // [4]=actual stack-change count
StructuredBuffer<uint> layer;           // [n_sc]
StructuredBuffer<uint> slot_for_index;  // [n_sc], absolute slot in pushes/pops_by_layer

RWStructuredBuffer<uint> match_for_index; // [n_sc]
RWStructuredBuffer<uint> out_valid;       // [1], ANDed on mismatch

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i_push = tid.x;
    uint n = min(gParams.n_sc, partial_parse_status[4u]);
    if (i_push >= n)
        return;

    uint code = sc_stream[i_push];
    if ((code & 1u) == 0u)
        return;

    uint l = layer[i_push];
    if (l >= gParams.n_layers)
        return;

    uint rank = 0u;
    for (uint j = 0u; j < i_push; j++)
    {
        if ((sc_stream[j] & 1u) == 1u && layer[j] == l)
            rank++;
    }
    if (rank >= hist_push[l] || rank >= hist_pop[l])
        return;

    uint i_pop = 0xFFFFFFFFu;
    uint pop_rank = 0u;
    for (uint j = 0u; j < n; j++)
    {
        if ((sc_stream[j] & 1u) != 0u || layer[j] != l)
            continue;
        if (pop_rank == rank)
        {
            i_pop = j;
            break;
        }
        pop_rank++;
    }
    if (i_pop == 0xFFFFFFFFu)
    {
        atomic_u32_and(out_valid, 0u, 0u);
        return;
    }

    match_for_index[i_push] = i_pop;
    match_for_index[i_pop] = i_push;

    if (gParams.typed_check != 0)
    {
        uint push_sym = sc_stream[i_push] >> 1u;
        uint pop_sym = sc_stream[i_pop] >> 1u;
        if (push_sym != pop_sym)
            atomic_u32_and(out_valid, 0u, 0u);
    }
}
