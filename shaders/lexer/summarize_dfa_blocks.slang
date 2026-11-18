// Per-block DFA transition summaries.
//
// One workgroup owns one 256-byte input block. The lanes first load the
// block's bytes and file-start flags into groupshared memory, so the walks
// below read one shared word per byte instead of two global loads. Lanes then
// compute three per-state chunk transition functions in parallel, and compose
// those chunk functions into the block transition function used by the
// inter-block scan.

#define WORKGROUP_SIZE 256
#define N_STATES 83
#define N_STATE_PACKS ((N_STATES + 3) / 4)
#define CHUNK_COUNT 3
#define CHUNK_WIDTH_CAP ((WORKGROUP_SIZE + CHUNK_COUNT - 1) / CHUNK_COUNT)

import shared.buffers.byte_packing;
import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> source_file_start_flags;
StructuredBuffer<uint> next_u8; // layout: [byte][state_pack] -> packed 4x u8 next states
RWStructuredBuffer<uint> block_summaries;
RWStructuredBuffer<uint> chunk_summary_out;

groupshared uint chunk_summaries[CHUNK_COUNT * N_STATES];
// Byte in bits 0..7, FILE_START_BIT when a source file starts at the byte.
groupshared uint block_bytes[WORKGROUP_SIZE];

static const uint FILE_START_BIT = 0x100u;

uint load_next_state(uint byte_value, uint state)
{
    uint packed = next_u8[byte_value * N_STATE_PACKS + (state >> 2u)];
    return packed_u8_at(packed, state & 3u);
}

bool is_file_start(uint i_abs)
{
    return source_file_start_flags[i_abs] != 0u;
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
    if (lane < block_len)
    {
        const uint i_abs = base + lane;
        block_bytes[lane] = load_byte_at(in_bytes, i_abs) |
                            (is_file_start(i_abs) ? FILE_START_BIT : 0u);
    }
    GroupMemoryBarrierWithGroupSync();

    if (lane < CHUNK_COUNT * N_STATES)
    {
        const uint chunk = lane / N_STATES;
        const uint state0 = lane - chunk * N_STATES;
        const uint chunk_width = (block_len + CHUNK_COUNT - 1u) / CHUNK_COUNT;
        const uint rel_begin = min(block_len, chunk * chunk_width);
        const uint rel_end = min(block_len, rel_begin + chunk_width);

        uint state = state0;
        for (uint offset = 0u; offset < CHUNK_WIDTH_CAP; offset += 1u)
        {
            const uint k = rel_begin + offset;
            if (k >= rel_end)
                break;
            const uint entry = block_bytes[k];
            if ((entry & FILE_START_BIT) != 0u)
                state = gParams.start_state;
            state = load_next_state(entry & 0xffu, state);
        }

        chunk_summaries[lane] = state;
        chunk_summary_out[(block * CHUNK_COUNT + chunk) * N_STATES + state0] = state;
    }
    GroupMemoryBarrierWithGroupSync();

    if (lane < N_STATES)
    {
        uint state = lane;
        for (uint chunk = 0u; chunk < CHUNK_COUNT; chunk += 1u)
        {
            state = chunk_summaries[chunk * N_STATES + state];
        }
        block_summaries[block * N_STATES + lane] = state;
    }
}
