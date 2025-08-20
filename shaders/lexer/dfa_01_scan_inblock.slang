// Per-block inclusive scan over δ_b functions represented as N_STATES-entry vectors.
// Writes: block_summaries[block] = composed function for the whole block.
//
// Ping–pong version without chunking:
// - Single barrier per stride, read from SRC plane and write to DST plane.
// - Keeps 2×16-bit packing and +1 stride padding to reduce bank conflicts.

#define WORKGROUP_SIZE 64
#define N_STATES 79                  // Must match Rust DFA state count
#define N_PACK4 ((N_STATES + 3) / 4) // # of uint words per row (4 x u8 per word)
#define N_PACK4_STRIDE (N_PACK4 + 1)

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
groupshared uint funcPing[WORKGROUP_SIZE][N_PACK4_STRIDE];
groupshared uint funcPong[WORKGROUP_SIZE][N_PACK4_STRIDE];

inline uint pack_quads(uint q0, uint q1, uint q2, uint q3)
{
    return (q0 & 0xFFu) | ((q1 & 0xFFu) << 8) | ((q2 & 0xFFu) << 16) | ((q3 & 0xFFu) << 24);
}

inline uint read8_from_src(uint pingAsSrc, uint row, uint idx)
{
    const uint w = (pingAsSrc != 0) ? funcPing[row][idx >> 2] : funcPong[row][idx >> 2];
    const uint sh = (idx & 3u) * 8u;
    return (w >> sh) & 0xFFu;
}

inline uint read_pack4_from_src(uint pingAsSrc, uint row, uint p)
{
    return (pingAsSrc != 0) ? funcPing[row][p] : funcPong[row][p];
}

inline void write_pack4_to_dst(uint pingAsSrc, uint row, uint p, uint packed)
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
        for (uint p = 0; p < N_PACK4; ++p)
        {
            const uint s0 = (p << 2);
            const uint s1 = s0 + 1u;
            const uint s2 = s0 + 2u;
            const uint s3 = s0 + 3u;

            // load s0/s1 and s2/s3 pairs (u16 packed with emit bit in MSB)
            const uint idx01 = b * N_STATES + s0;
            const uint idx23 = b * N_STATES + s2;
            const uint pair01 = load_u32_two_u16(next_emit, idx01);
            const uint pair23 = load_u32_two_u16(next_emit, idx23);

            const uint v0 = pair01 & 0x7FFFu;
            const uint v1 = (pair01 >> 16) & 0x7FFFu;
            const uint v2 = pair23 & 0x7FFFu;
            const uint v3 = (pair23 >> 16) & 0x7FFFu;

            const uint q0 = (s0 < N_STATES) ? (v0 & 0xFFu) : (s0 & 0xFFu);
            const uint q1 = (s1 < N_STATES) ? (v1 & 0xFFu) : (s1 & 0xFFu);
            const uint q2 = (s2 < N_STATES) ? (v2 & 0xFFu) : (s2 & 0xFFu);
            const uint q3 = (s3 < N_STATES) ? (v3 & 0xFFu) : (s3 & 0xFFu);

            funcPing[tid.x][p] = pack_quads(q0, q1, q2, q3);
        }
    }
    else
    {
        // Identity for out-of-range lanes
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            const uint s0 = (p << 2);
            const uint s1 = s0 + 1u;
            const uint s2 = s0 + 2u;
            const uint s3 = s0 + 3u;
            funcPing[tid.x][p] = pack_quads(s0 & 0xFFu, s1 & 0xFFu, (s2 < N_STATES ? (s2 & 0xFFu) : 0u), (s3 < N_STATES ? (s3 & 0xFFu) : 0u));
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
            for (uint p = 0; p < N_PACK4; ++p)
            {
                const uint srcPacked = read_pack4_from_src(pingAsSrc, srcRow, p);
                const uint a0 = (srcPacked >> 0) & 0xFFu;
                const uint a1 = (srcPacked >> 8) & 0xFFu;
                const uint a2 = (srcPacked >> 16) & 0xFFu;
                const uint a3 = (srcPacked >> 24) & 0xFFu;

                const uint r0 = read8_from_src(pingAsSrc, tid.x, a0);
                const uint r1 = read8_from_src(pingAsSrc, tid.x, a1);
                const uint r2 = read8_from_src(pingAsSrc, tid.x, a2);
                const uint r3 = read8_from_src(pingAsSrc, tid.x, a3);

                write_pack4_to_dst(pingAsSrc, tid.x, p, pack_quads(r0, r1, r2, r3));
            }
        }
        else
        {
            // Rows below offset remain unchanged this round: copy through
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                write_pack4_to_dst(pingAsSrc, tid.x, p, read_pack4_from_src(pingAsSrc, tid.x, p));
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
                const uint w = (srcIsPing != 0) ? funcPing[tid.x][s >> 2] : funcPong[tid.x][s >> 2];
                const uint sh = (s & 3u) * 8u;
                const uint v = (w >> sh) & 0xFFu;
                block_summaries[dstBase + s] = v;
            }
        }
    }
}
