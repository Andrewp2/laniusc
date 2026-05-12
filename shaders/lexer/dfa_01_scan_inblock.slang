// Per-block DFA transition summaries.
//
// One workgroup owns one 256-byte input block. Lanes compute three per-state
// chunk transition functions in parallel, then compose those chunk functions
// into the block transition function used by the inter-block scan.

#define WORKGROUP_SIZE 256
#define N_STATES 80
#define CHUNK_COUNT 3

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> source_file_count;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> next_u8; // layout: [state_pack][byte] -> packed 4x u8 next states
RWStructuredBuffer<uint> block_summaries;
RWStructuredBuffer<uint> chunk_summary_out;

static const uint MAX_FILES_SCAN = 1024u;

groupshared uint chunk_summaries[CHUNK_COUNT * N_STATES];

uint load_next_state(uint byte_value, uint state)
{
    uint packed = next_u8[(state >> 2u) * 256u + byte_value];
    return (packed >> ((state & 3u) * 8u)) & 0xFFu;
}

bool is_file_start(uint i_abs)
{
    uint files = min(source_file_count[0], MAX_FILES_SCAN);
    [loop]
    for (uint f = 0u; f < files; f += 1u)
    {
        if (source_file_start[f] == i_abs)
            return true;
    }
    return false;
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_01_scan_inblock(uint3 tid: SV_GroupThreadID,
                         uint3 /*gid*/: SV_DispatchThreadID,
                         uint3 ggrp: SV_GroupID)
{
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = min(nb, 65535u);
    const uint block = ggrp.y * groupsX + ggrp.x;
    const uint base = block * WORKGROUP_SIZE;

    const uint block_len = (base < gParams.n) ? min(WORKGROUP_SIZE, gParams.n - base) : 0u;
    if (block >= nb || block_len == 0u)
        return;

    const uint lane = tid.x;
    if (lane < CHUNK_COUNT * N_STATES)
    {
        const uint chunk = lane / N_STATES;
        const uint state0 = lane - chunk * N_STATES;
        const uint chunk_width = (block_len + CHUNK_COUNT - 1u) / CHUNK_COUNT;
        const uint rel_begin = min(block_len, chunk * chunk_width);
        const uint rel_end = min(block_len, rel_begin + chunk_width);

        uint state = state0;
        [loop]
        for (uint k = rel_begin; k < rel_end; k += 1u)
        {
            uint i_abs = base + k;
            if (is_file_start(i_abs))
                state = gParams.start_state;
            uint b = load_byte_at(in_bytes, base + k);
            state = load_next_state(b, state);
        }

        chunk_summaries[lane] = state;
        chunk_summary_out[(block * CHUNK_COUNT + chunk) * N_STATES + state0] = state;
    }
    GroupMemoryBarrierWithGroupSync();

    if (lane < N_STATES)
    {
        uint state = lane;
        [unroll]
        for (uint chunk = 0u; chunk < CHUNK_COUNT; chunk += 1u)
        {
            state = chunk_summaries[chunk * N_STATES + state];
        }
        block_summaries[block * N_STATES + lane] = state;
    }
}
