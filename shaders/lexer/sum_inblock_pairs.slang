// shaders/lexer/sum_inblock_pairs.slang
// Sum both seed streams (ALL, KEPT) inside each 256-wide block in shared memory.
// Writes per-element in-block prefix and a single uint2 block total.

#define WORKGROUP_SIZE 256

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

// --------- CHANGED: read packed flags instead of two seed buffers ---------
StructuredBuffer<uint> flags_packed; // length n

RWStructuredBuffer<uint2> s_pair_inblock;    // length n (prefix within block)
RWStructuredBuffer<uint2> block_totals_pair; // length nb (sum of this block)

groupshared uint2 sh[WORKGROUP_SIZE];

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void sum_inblock_pairs(uint3 tid: SV_GroupThreadID,
                       uint3 gid: SV_DispatchThreadID,
                       uint3 ggrp: SV_GroupID)
{
    const uint block = ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // Load (ALL, KEPT) pair or 0 if out-of-range
    uint2 v = uint2(0u, 0u);
    if (i < gParams.n)
    {
        uint f = flags_packed[i];
        v = seeds_from_flags(f);
    }
    sh[tid.x] = v;
    GroupMemoryBarrierWithGroupSync();

    // Standard Hillis–Steele inclusive scan in shared memory (add on uint2)
    for (uint offset = 1u; offset < WORKGROUP_SIZE; offset <<= 1u)
    {
        uint2 tmp = sh[tid.x];
        if (tid.x >= offset)
        {
            tmp += sh[tid.x - offset];
        }
        GroupMemoryBarrierWithGroupSync();
        sh[tid.x] = tmp;
        GroupMemoryBarrierWithGroupSync();
    }

    // Store in-block prefix if in range
    if (i < gParams.n)
    {
        s_pair_inblock[i] = sh[tid.x];
    }

    // One lane writes the block total = prefix of the last valid element
    const uint remain = (gParams.n > base) ? (gParams.n - base) : 0u;
    const uint count = remain < WORKGROUP_SIZE ? remain : WORKGROUP_SIZE;
    if (count > 0u)
    {
        const uint last_lane = count - 1u;
        if (tid.x == last_lane)
        {
            block_totals_pair[block] = sh[last_lane];
        }
    }
}
