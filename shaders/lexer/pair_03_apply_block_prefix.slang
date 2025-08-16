// shaders/lexer/sum_apply_block_prefix_downsweep_pairs.slang
// Add the block-level inclusive prefix (carry from previous blocks) to an
// in-block inclusive scan we recompute from flags, then write final ALL/KEPT sums.

#define WORKGROUP_SIZE 256

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> flags_packed;       // length n (packed flags per i)
StructuredBuffer<uint2> block_prefix_pair; // length nb (inclusive per block)

RWStructuredBuffer<uint> s_all_final;  // length n
RWStructuredBuffer<uint> s_keep_final; // length n

groupshared uint2 sh[WORKGROUP_SIZE];

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void pair_03_apply_block_prefix(uint3 tid: SV_GroupThreadID,
                                uint3 gid: SV_DispatchThreadID,
                                uint3 ggrp: SV_GroupID)
{
    const uint block = ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // Load per-thread (ALL, KEPT) seeds and do an in-block inclusive scan
    uint2 v = uint2(0u, 0u);
    if (i < gParams.n)
    {
        uint f = flags_packed[i];
        v = seeds_from_flags(f);
    }
    sh[tid.x] = v;
    GroupMemoryBarrierWithGroupSync();

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

    if (i >= gParams.n)
        return;

    // Carry = inclusive prefix of all prior blocks
    uint2 carry = uint2(0u, 0u);
    if (block > 0u)
    {
        carry = block_prefix_pair[block - 1u];
    }

    uint2 res = sh[tid.x] + carry;
    s_all_final[i] = res.x;
    s_keep_final[i] = res.y;
}
