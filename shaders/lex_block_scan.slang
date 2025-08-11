// shaders/lex_block_scan.slang
// Per-block inclusive scan over δ_b functions represented as 32-entry vectors.
// Writes: block_summaries[block] = composed function for the whole block.
// Optionally writes f_inblock[i] = state(start) after in-block prefix i.

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
StructuredBuffer<uint> next_state;        // 256 * N_STATES, layout: b*N_STATES + s
RWStructuredBuffer<uint> f_inblock;       // optional debug/scratch (state per element)
RWStructuredBuffer<uint> block_summaries; // nb * N_STATES

groupshared uint func[WORKGROUP_SIZE][N_STATES];

[numthreads(WORKGROUP_SIZE, 1, 1)]
void block_scan(uint3 tid: SV_GroupThreadID,
                uint3 gid: SV_DispatchThreadID,
                uint3 ggrp: SV_GroupID)
{
    const uint block = ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // Load per-element δ_b into shared memory
    uint b = 0;
    if (i < gParams.n)
    {
        b = in_bytes[i] & 0xFFu;
        // func[i][s] = next_state[b][s]
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            func[tid.x][s] = next_state[b * N_STATES + s];
        }
    }
    else
    {
        // identity for out-of-range lanes
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            func[tid.x][s] = s;
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // Inclusive scan in shared memory with composition: C = B ∘ A ; C[s] = B[A[s]]
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

    // Optionally store in-block state result from start
    if (i < gParams.n)
    {
        f_inblock[i] = func[tid.x][gParams.start_state];
    }

    // Thread lane last writes the block summary vector
    if (tid.x == WORKGROUP_SIZE - 1)
    {
        uint dstBase = block * N_STATES;
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            block_summaries[dstBase + s] = func[tid.x][s];
        }
    }
}
