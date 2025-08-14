// Re-run the in-block prefix with the block carry (inclusive prefix of prior blocks).

#define WORKGROUP_SIZE 256
#define N_STATES 32

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;       // byte-addressable input
StructuredBuffer<uint> next_emit; // 2x u16 per uint
StructuredBuffer<uint> block_prefix;
RWStructuredBuffer<uint> f_final;

groupshared uint func[WORKGROUP_SIZE][N_STATES];

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void apply_block_prefix_downsweep(uint3 tid: SV_GroupThreadID,
                                  uint3 gid: SV_DispatchThreadID,
                                  uint3 ggrp: SV_GroupID)
{
    const uint block = ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // Carry is inclusive prefix of previous block:
    // carry = identity for block==0, else block_prefix[block-1]
    uint carry_state0 = gParams.start_state;
    if (block > 0)
    {
        uint prevBase = (block - 1) * N_STATES;
        carry_state0 = block_prefix[prevBase + carry_state0];
    }

    // Load functions for this block
    uint b = 0;
    if (i < gParams.n)
    {
        b = load_byte_at(in_bytes, i);
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            uint packed = load_u16_packed(next_emit, b * N_STATES + s);
            func[tid.x][s] = packed & 0x7FFFu;
        }
    }
    else
    {
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            func[tid.x][s] = s;
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // Inclusive scan of functions within the block
    for (uint offset = 1; offset < WORKGROUP_SIZE; offset <<= 1)
    {
        uint tmp[N_STATES];
        if (tid.x >= offset)
        {
            [unroll]
            for (uint s = 0; s < N_STATES; ++s)
            {
                uint a = func[tid.x - offset][s];
                tmp[s] = func[tid.x][a];
            }
        }
        else
        {
            [unroll]
            for (uint s = 0; s < N_STATES; ++s)
            {
                tmp[s] = func[tid.x][s];
            }
        }
        GroupMemoryBarrierWithGroupSync();
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            func[tid.x][s] = tmp[s];
        }
        GroupMemoryBarrierWithGroupSync();
    }

    // Apply in-block prefix function to carry(start)
    if (i < gParams.n)
    {
        f_final[i] = func[tid.x][carry_state0];
    }
}
