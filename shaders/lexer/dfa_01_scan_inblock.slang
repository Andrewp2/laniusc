// Per-block inclusive scan over δ_b functions represented as N_STATES-entry vectors.
// Writes: block_summaries[block] = composed function for the whole block.
//
// Ping–pong version without chunking:
// - Single barrier per stride, read from SRC plane and write to DST plane.
// - Keeps 2×16-bit packing and +1 stride padding to reduce bank conflicts.

#define WORKGROUP_SIZE 64
#define N_STATES 32                 // OK to raise (e.g., 40)
#define N_PACK ((N_STATES + 1) / 2) // # of uint words per row (2 x 16b per word)
#define N_PACK_STRIDE (N_PACK + 1)

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;       // byte-addressable input
StructuredBuffer<uint> next_emit; // 2x u16 per uint (low15=next, high1=emit)
RWStructuredBuffer<uint> block_summaries;

// Two planes in groupshared (ping/pong)
groupshared uint funcPing[WORKGROUP_SIZE][N_PACK_STRIDE];
groupshared uint funcPong[WORKGROUP_SIZE][N_PACK_STRIDE];

inline uint pack_pair(uint lo16, uint hi16)
{
    return (lo16 & 0xFFFFu) | ((hi16 & 0xFFFFu) << 16);
}

inline uint read16_from_src(uint pingAsSrc, uint row, uint idx)
{
    const uint w = pingAsSrc != 0 ? funcPing[row][idx >> 1] : funcPong[row][idx >> 1];
    return ((idx & 1u) != 0u) ? ((w >> 16) & 0xFFFFu) : (w & 0xFFFFu);
}

inline uint read_pack_from_src(uint pingAsSrc, uint row, uint p)
{
    return (pingAsSrc != 0) ? funcPing[row][p] : funcPong[row][p];
}

inline void write_pack_to_dst(uint pingAsSrc, uint row, uint p, uint packed)
{
    if (pingAsSrc != 0)
    {
        funcPong[row][p] = packed;
    }
    else
    {
        funcPing[row][p] = packed;
    }
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_01_scan_inblock(uint3 tid: SV_GroupThreadID,
                         uint3 gid: SV_DispatchThreadID,
                         uint3 ggrp: SV_GroupID)
{
    // --- 2D dispatch linearization (tile by WORKGROUPS, not elements) ---
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = min(nb, 65535u);

    const uint block = ggrp.y * groupsX + ggrp.x; // linear block index
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // --- Load δ_b row into Ping as packed pairs ---
    if (i < gParams.n)
    {
        const uint b = load_byte_at(in_bytes, i);
        [unroll]
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;

            const uint word = next_emit[(b * N_STATES + s0) >> 1];
            const uint lo = word & 0x7FFFu;
            const uint hi = (word >> 16) & 0x7FFFu;

            funcPing[tid.x][p] = pack_pair(lo, (s1 < N_STATES) ? hi : 0u);
        }
    }
    else
    {
        // Identity for out-of-range lanes
        [unroll]
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;
            funcPing[tid.x][p] = pack_pair(s0, (s1 < N_STATES) ? s1 : 0u);
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // --- Inclusive scan over rows (functions): C = B ∘ A ---
    uint pingAsSrc = 1u; // read from Ping, write to Pong
    for (uint offset = 1u; offset < WORKGROUP_SIZE; offset <<= 1u)
    {
        const bool active = (tid.x >= offset);
        const uint srcRow = tid.x - offset;

        if (active)
        {
            [unroll]
            for (uint p = 0; p < N_PACK; ++p)
            {
                const uint srcPacked = read_pack_from_src(pingAsSrc, srcRow, p);
                const uint a0 = srcPacked & 0xFFFFu;
                const uint a1 = (srcPacked >> 16) & 0xFFFFu;

                const uint r0 = read16_from_src(pingAsSrc, tid.x, a0);
                const uint r1 = read16_from_src(pingAsSrc, tid.x, a1); // safe; last pack’s hi lane was zeroed

                write_pack_to_dst(pingAsSrc, tid.x, p, pack_pair(r0, r1));
            }
        }
        else
        {
            // Rows below offset remain unchanged this round: copy through
            [unroll]
            for (uint p = 0; p < N_PACK; ++p)
            {
                write_pack_to_dst(pingAsSrc, tid.x, p, read_pack_from_src(pingAsSrc, tid.x, p));
            }
        }

        GroupMemoryBarrierWithGroupSync(); // ensure DST visible to next round
        pingAsSrc ^= 1u;                   // flip planes
    }

    // --- Write block summary from the final SRC plane (after last flip) ---
    if (tid.x == WORKGROUP_SIZE - 1u)
    {
        if (block < nb)
        {
            const uint srcIsPing = pingAsSrc;
            const uint dstBase = block * N_STATES;
            [unroll]
            for (uint s = 0; s < N_STATES; ++s)
            {
                const uint w = (srcIsPing != 0) ? funcPing[tid.x][s >> 1] : funcPong[tid.x][s >> 1];
                const uint v = ((s & 1u) != 0u) ? ((w >> 16) & 0xFFFFu) : (w & 0xFFFFu);
                block_summaries[dstBase + s] = v;
            }
        }
    }
}
