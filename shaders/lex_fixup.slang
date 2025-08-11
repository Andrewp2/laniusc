// shaders/lex_fixup.slang
// Re-run the in-block prefix with the block carry (inclusive prefix of prior blocks).

#define WORKGROUP_SIZE 128
#define N_STATES 32

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> in_bytes;
StructuredBuffer<uint> next_state;   // 256 * N_STATES
StructuredBuffer<uint> block_prefix; // nb * N_STATES (inclusive)

RWStructuredBuffer<uint> f_final; // final state per element (global)

groupshared uint func[WORKGROUP_SIZE][N_STATES];

[numthreads(WORKGROUP_SIZE, 1, 1)]
void fixup_prefix(uint3 tid: SV_GroupThreadID,
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
        b = in_bytes[i] & 0xFFu;
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            func[tid.x][s] = next_state[b * N_STATES + s];
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
