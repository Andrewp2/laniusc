// shaders/parser/brackets_pse_04_pair_by_layer.slang
// PSE pairing via rank-by-layer (equivalent to predecessor-on-depth for well-formed streams).
// Inputs assume you've already run passes 01..03 to compute global depth and `layer[i]`.

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
StructuredBuffer<uint> layer;           // [n_sc]
StructuredBuffer<uint> slot_for_index;  // [n_sc], absolute slot in pushes/pops_by_layer

RWStructuredBuffer<uint> match_for_index; // [n_sc]
RWStructuredBuffer<uint> out_valid;       // [1], ANDed on mismatch

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i_push = tid.x;
    if (i_push >= gParams.n_sc)
        return;

    uint code = sc_stream[i_push];
    if ((code & 1u) == 0u)
        return;

    uint l = layer[i_push];
    if (l >= gParams.n_layers)
        return;

    uint p0 = off_push[l];
    uint q0 = off_pop[l];
    uint slot = slot_for_index[i_push];
    if (slot < p0)
        return;
    uint rank = slot - p0;
    if (rank >= hist_push[l] || rank >= hist_pop[l])
        return;

    uint i_pop = pops_by_layer[q0 + rank];

    match_for_index[i_push] = i_pop;
    match_for_index[i_pop] = i_push;

    if (gParams.typed_check != 0)
    {
        uint push_sym = sc_stream[i_push] >> 1u;
        uint pop_sym = sc_stream[i_pop] >> 1u;
        if (push_sym != pop_sym)
            InterlockedAnd(out_valid[0], 0u);
    }
}
