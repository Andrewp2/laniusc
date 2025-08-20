// Per-block inclusive scan over δ_b functions represented as N_STATES-entry vectors (u8 packed).
// Writes: block_summaries[block] = composed function for the whole block.

#define WORKGROUP_SIZE 256
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

ByteAddressBuffer in_bytes;     // byte-addressable input
StructuredBuffer<uint> next_u8; // packed 4x u8 next-state per uint, layout: [pack][byte]
RWStructuredBuffer<uint> block_summaries;

// Single plane; in-place scan with per-thread caches
groupshared uint funcArr[WORKGROUP_SIZE][N_PACK4_STRIDE];

inline uint pack_quads(uint q0, uint q1, uint q2, uint q3)
{
    return (q0 & 0xFFu) | ((q1 & 0xFFu) << 8) | ((q2 & 0xFFu) << 16) | ((q3 & 0xFFu) << 24);
}

inline uint read8_from_row(uint row, uint idx)
{
    const uint w = funcArr[row][idx >> 2];
    const uint sh = (idx & 3u) * 8u;
    return (w >> sh) & 0xFFu;
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_01_scan_inblock(uint3 tid: SV_GroupThreadID,
                         uint3 gid: SV_DispatchThreadID,
                         uint3 ggrp: SV_GroupID)
{
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = min(nb, 65535u);

    const uint block = ggrp.y * groupsX + ggrp.x; // linear block index
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // Load δ_b row into shared
    if (i < gParams.n)
    {
        const uint b = load_byte_at(in_bytes, i);
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            const uint w = next_u8[p * 256u + b];
            const uint q0 = (w >> 0) & 0xFFu;
            const uint q1 = (w >> 8) & 0xFFu;
            const uint q2 = (w >> 16) & 0xFFu;
            const uint q3 = (w >> 24) & 0xFFu;
            funcArr[tid.x][p] = pack_quads(q0, q1, q2, q3);
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
            funcArr[tid.x][p] = pack_quads(s0 & 0xFFu, s1 & 0xFFu, (s2 < N_STATES ? (s2 & 0xFFu) : 0u), (s3 < N_STATES ? (s3 & 0xFFu) : 0u));
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // Inclusive scan in-place: C = B ∘ A
    for (uint offset = 1u; offset < WORKGROUP_SIZE; offset <<= 1u)
    {
        const bool active = (tid.x >= offset);
        const uint srcRow = tid.x - offset;

        // Cache my row and source row
        uint myRowCache[N_PACK4];
        uint srcRowCache[N_PACK4];
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            myRowCache[p] = funcArr[tid.x][p];
            srcRowCache[p] = funcArr[srcRow][p];
        }
        GroupMemoryBarrierWithGroupSync();

        if (active)
        {
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                const uint srcPacked = srcRowCache[p];
                const uint a0 = (srcPacked >> 0) & 0xFFu;
                const uint a1 = (srcPacked >> 8) & 0xFFu;
                const uint a2 = (srcPacked >> 16) & 0xFFu;
                const uint a3 = (srcPacked >> 24) & 0xFFu;

                const uint w0 = myRowCache[a0 >> 2];
                const uint w1 = myRowCache[a1 >> 2];
                const uint w2 = myRowCache[a2 >> 2];
                const uint w3 = myRowCache[a3 >> 2];
                const uint r0 = (w0 >> ((a0 & 3u) * 8u)) & 0xFFu;
                const uint r1 = (w1 >> ((a1 & 3u) * 8u)) & 0xFFu;
                const uint r2 = (w2 >> ((a2 & 3u) * 8u)) & 0xFFu;
                const uint r3 = (w3 >> ((a3 & 3u) * 8u)) & 0xFFu;

                funcArr[tid.x][p] = pack_quads(r0, r1, r2, r3);
            }
        }

        GroupMemoryBarrierWithGroupSync();
    }

    // Write block summary from my final row
    if (tid.x == WORKGROUP_SIZE - 1u)
    {
        if (block < nb)
        {
            const uint dstBase = block * N_STATES;
            [unroll]
            for (uint s = 0; s < N_STATES; ++s)
            {
                const uint w = funcArr[tid.x][s >> 2];
                const uint sh = (s & 3u) * 8u;
                const uint v = (w >> sh) & 0xFFu;
                block_summaries[dstBase + s] = v;
            }
        }
    }
}
