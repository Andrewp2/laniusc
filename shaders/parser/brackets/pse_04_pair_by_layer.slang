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
RWStructuredBuffer<uint> pushes_by_layer; // [sum hist_push]
RWStructuredBuffer<uint> pops_by_layer;   // [sum hist_pop]
StructuredBuffer<uint> sc_stream;       // [n_sc]
StructuredBuffer<uint> partial_parse_status; // [4]=actual stack-change count
StructuredBuffer<uint> layer;           // [n_sc]
RWStructuredBuffer<uint> slot_for_index;  // [n_sc], absolute slot in pushes/pops_by_layer

RWStructuredBuffer<uint> match_for_index; // [n_sc]
RWStructuredBuffer<uint> out_valid;       // [1], ANDed on mismatch

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint SMALL_PAIR_CAPACITY = 2048u;
static const uint RADIX_PAIR_CAPACITY = 0x7fffffffu;

groupshared uint small_pair_layer_counts[SMALL_PAIR_CAPACITY];
groupshared uint small_pair_tile_keys[WG_SIZE];

void pair_small_stream(uint lane, uint n)
{
    for (uint i = lane; i < SMALL_PAIR_CAPACITY; i += WG_SIZE)
        small_pair_layer_counts[i] = 0u;
    GroupMemoryBarrierWithGroupSync();

    for (uint tile_begin = 0u; tile_begin < n; tile_begin += WG_SIZE)
    {
        uint i = tile_begin + lane;
        uint l = i < n ? layer[i] : INVALID;
        bool is_push = i < n && (sc_stream[i] & 1u) == 1u;
        uint key = l < gParams.n_layers ? (l << 1u) | (is_push ? 0u : 1u) : INVALID;
        small_pair_tile_keys[lane] = key;
        GroupMemoryBarrierWithGroupSync();

        uint rank = 0u;
        uint slot = INVALID;
        if (key != INVALID)
        {
            uint packed_counts = small_pair_layer_counts[l];
            rank = is_push ? packed_counts & 0xffffu : packed_counts >> 16u;
            for (uint prior_lane = 0u; prior_lane < lane; prior_lane += 1u)
                rank += small_pair_tile_keys[prior_lane] == key ? 1u : 0u;
            slot = (is_push ? off_push[l] : off_pop[l]) + rank;
            if (slot < n)
            {
                if (is_push)
                    pushes_by_layer[slot] = i;
                else
                    pops_by_layer[slot] = i;
                slot_for_index[i] = slot;
            }
        }
        GroupMemoryBarrierWithGroupSync();

        if (key != INVALID)
        {
            uint increment = is_push ? 1u : 0x10000u;
            uint ignored;
            InterlockedAdd(small_pair_layer_counts[l], increment, ignored);
        }
        GroupMemoryBarrierWithGroupSync();
    }

    for (uint i_push = lane; i_push < n; i_push += WG_SIZE)
    {
        if ((sc_stream[i_push] & 1u) == 0u)
            continue;

        uint l = layer[i_push];
        if (l >= gParams.n_layers)
            continue;

        uint push_slot = slot_for_index[i_push];
        uint rank = push_slot >= off_push[l] ? push_slot - off_push[l] : INVALID;
        if (rank >= hist_push[l] || rank >= hist_pop[l])
            continue;

        uint pop_slot = off_pop[l] + rank;
        uint i_pop = pop_slot < n ? pops_by_layer[pop_slot] : INVALID;
        if (i_pop >= n)
        {
            atomic_u32_and(out_valid, 0u, 0u);
            continue;
        }

        match_for_index[i_push] = i_pop;
        match_for_index[i_pop] = i_push;
        if (gParams.typed_check != 0u &&
            (sc_stream[i_push] >> 1u) != (sc_stream[i_pop] >> 1u))
        {
            atomic_u32_and(out_valid, 0u, 0u);
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(
    uint3 tid: SV_DispatchThreadID,
    uint3 ltid: SV_GroupThreadID,
    uint3 gid: SV_GroupID)
{
    uint n = min(gParams.n_sc, partial_parse_status[4u]);
    if (n <= SMALL_PAIR_CAPACITY)
    {
        if (gid.x == 0u)
            pair_small_stream(ltid.x, n);
        return;
    }

    uint i_push = tid.x;
    if (i_push >= n)
        return;

    uint code = sc_stream[i_push];
    if ((code & 1u) == 0u)
        return;

    uint l = layer[i_push];
    if (l >= gParams.n_layers)
        return;

    if (n <= RADIX_PAIR_CAPACITY)
    {
        uint sorted_pos = slot_for_index[i_push];
        uint group_begin = off_push[l] + off_pop[l];
        uint rank = sorted_pos >= group_begin ? sorted_pos - group_begin : INVALID;
        if (rank >= hist_push[l] || rank >= hist_pop[l])
            return;

        uint pop_sorted_pos = group_begin + hist_push[l] + rank;
        uint i_pop = pop_sorted_pos < n ? pushes_by_layer[pop_sorted_pos] : INVALID;
        if (i_pop >= n || (sc_stream[i_pop] & 1u) != 0u || layer[i_pop] != l)
        {
            atomic_u32_and(out_valid, 0u, 0u);
            return;
        }

        match_for_index[i_push] = i_pop;
        match_for_index[i_pop] = i_push;
        if (gParams.typed_check != 0u &&
            (sc_stream[i_push] >> 1u) != (sc_stream[i_pop] >> 1u))
        {
            atomic_u32_and(out_valid, 0u, 0u);
        }
        return;
    }

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
