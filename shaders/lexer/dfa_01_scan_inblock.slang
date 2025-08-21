// Per-block composition of δ_b functions (each row: N_STATES x u8).
// Output: block_summaries[block] = δ_block for that 256-byte block.
//
// Wave-size fixed at 32 (RTX 3090).
// This revision:
//   * Removes CTA barriers inside the wave-local tree reduction.
//   * Adds 1 column of padding to gRows second dimension to reduce bank conflicts.
//   * Keeps exactly one CTA-wide sync before the inter-wave carry.
//   * Unrolls short loops.
//
// Constraints: workgroup=256, wave size=32 only.

#define WORKGROUP_SIZE 256
#define WAVE_SIZE 32u
#define N_STATES 79
#define N_PACK4 ((N_STATES + 3) / 4)           // 20
#define MAX_WAVES (WORKGROUP_SIZE / WAVE_SIZE) // 8

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> next_u8; // layout: [pack][byte] -> uint(packed 4x u8)
RWStructuredBuffer<uint> block_summaries;

// Per-wave totals and carries
groupshared uint sgTotals[MAX_WAVES][N_PACK4];
groupshared uint sgCarries[MAX_WAVES][N_PACK4];

// Staging for the reduction: one row per thread, 20 packs per row (+1 pad to ease bank conflicts)
groupshared uint gRows[WORKGROUP_SIZE][N_PACK4 + 1];

inline uint pack_quads(uint q0, uint q1, uint q2, uint q3)
{
    return (q0 & 0xFFu) | ((q1 & 0xFFu) << 8) | ((q2 & 0xFFu) << 16) | ((q3 & 0xFFu) << 24);
}

inline uint identity_pack(uint p)
{
    const uint s0 = (p << 2);
    const uint s1 = s0 + 1u;
    const uint s2 = s0 + 2u;
    const uint s3 = s0 + 3u;
    return pack_quads(
        (s0 & 0xFFu),
        (s1 & 0xFFu),
        (s2 < N_STATES ? (s2 & 0xFFu) : 0u),
        (s3 < N_STATES ? (s3 & 0xFFu) : 0u));
}

// Compose a single pack L with the partner lane's row stored in gRows[partnerLane][*].
// Returns R ∘ L, where R is the partner's row-function, L is our current pack.
inline uint compose_pack_with_partner_smem(uint LrowPack, uint partnerLane)
{
    const uint a0 = (LrowPack) & 0xFFu;
    const uint a1 = ((LrowPack >> 8) & 0xFFu);
    const uint a2 = ((LrowPack >> 16) & 0xFFu);
    const uint a3 = (LrowPack >> 24) & 0xFFu;

    const uint w0 = gRows[partnerLane][a0 >> 2];
    const uint w1 = gRows[partnerLane][a1 >> 2];
    const uint w2 = gRows[partnerLane][a2 >> 2];
    const uint w3 = gRows[partnerLane][a3 >> 2];

    const uint r0 = (w0 >> ((a0 & 3u) * 8u)) & 0xFFu;
    const uint r1 = (w1 >> ((a1 & 3u) * 8u)) & 0xFFu;
    const uint r2 = (w2 >> ((a2 & 3u) * 8u)) & 0xFFu;
    const uint r3 = (w3 >> ((a3 & 3u) * 8u)) & 0xFFu;

    return pack_quads(r0, r1, r2, r3);
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
    const uint tIdx = tid.x;              // 0..255
    const uint lane = WaveGetLaneIndex(); // 0..31
    const uint waveId = tIdx / WAVE_SIZE; // 0..7
    const uint inHalf = lane & 15u;       // 0..15
    const uint i = base + tIdx;

    const uint block_len = (base < gParams.n) ? min(WORKGROUP_SIZE, gParams.n - base) : 0u;
    if (block >= nb || block_len == 0u)
        return;

    // ---- Build our δ_b row and stage to shared memory (no large live arrays) ----
    if (tIdx < block_len)
    {
        const uint b = load_byte_at(in_bytes, i);
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            gRows[tIdx][p] = next_u8[p * 256u + b];
        }
    }
    else
    {
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            gRows[tIdx][p] = identity_pack(p);
        }
    }

    // Optional: fence to keep writes ordered before the wave-local reads that follow (no sync).
    GroupMemoryBarrier();

    // ---------------- Half-warp tree reduction in SMEM (d = 1,2,4,8) ----------------
    // Waves execute in lockstep; no barriers required inside these stages.
    {
        // d = 1
        {
            const uint d = 1u;
            const bool isHead = ((inHalf & ((d << 1) - 1u)) == 0u);
            const uint partnerLane = (tIdx ^ d);
            if (isHead)
            {
                [unroll]
                for (uint p = 0; p < N_PACK4; ++p)
                {
                    const uint L = gRows[tIdx][p];
                    gRows[tIdx][p] = compose_pack_with_partner_smem(L, partnerLane);
                }
            }
        }
        // d = 2
        {
            const uint d = 2u;
            const bool isHead = ((inHalf & ((d << 1) - 1u)) == 0u);
            const uint partnerLane = (tIdx ^ d);
            if (isHead)
            {
                [unroll]
                for (uint p = 0; p < N_PACK4; ++p)
                {
                    const uint L = gRows[tIdx][p];
                    gRows[tIdx][p] = compose_pack_with_partner_smem(L, partnerLane);
                }
            }
        }
        // d = 4
        {
            const uint d = 4u;
            const bool isHead = ((inHalf & ((d << 1) - 1u)) == 0u);
            const uint partnerLane = (tIdx ^ d);
            if (isHead)
            {
                [unroll]
                for (uint p = 0; p < N_PACK4; ++p)
                {
                    const uint L = gRows[tIdx][p];
                    gRows[tIdx][p] = compose_pack_with_partner_smem(L, partnerLane);
                }
            }
        }
        // d = 8
        {
            const uint d = 8u;
            const bool isHead = ((inHalf & ((d << 1) - 1u)) == 0u);
            const uint partnerLane = (tIdx ^ d);
            if (isHead)
            {
                [unroll]
                for (uint p = 0; p < N_PACK4; ++p)
                {
                    const uint L = gRows[tIdx][p];
                    gRows[tIdx][p] = compose_pack_with_partner_smem(L, partnerLane);
                }
            }
        }
    }

    // ---------------- Final cross-half compose: lane 0 ∘ lane 16 ----------------
    if (lane == 0u)
    {
        const uint partnerLane = (tIdx ^ 16u); // 0 <-> 16
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            const uint L = gRows[tIdx][p];
            gRows[tIdx][p] = compose_pack_with_partner_smem(L, partnerLane);
        }
    }

    // Publish per-wave total from lane 0
    if (lane == 0u)
    {
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
            sgTotals[waveId][p] = gRows[tIdx][p];
    }

    // Inter-wave sync (tid.x==0 will read sgTotals)
    GroupMemoryBarrierWithGroupSync();

    // ---------------- Serial carry across active waves on tid.x==0, then write summary -----
    if (tIdx == 0u)
    {
        const uint numActiveWaves = (block_len + (WAVE_SIZE - 1u)) / WAVE_SIZE;

        if (numActiveWaves > 0u)
        {
            // carry[0] = I
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
                sgCarries[0][p] = identity_pack(p);

            // carry[w] = sgTotals[w-1] ∘ carry[w-1]
            for (uint w = 1u; w < numActiveWaves; ++w)
            {
                [unroll]
                for (uint p = 0; p < N_PACK4; ++p)
                {
                    const uint carryPacked = sgCarries[w - 1u][p];

                    const uint a0 = (carryPacked) & 0xFFu;
                    const uint a1 = (carryPacked >> 8) & 0xFFu;
                    const uint a2 = (carryPacked >> 16) & 0xFFu;
                    const uint a3 = (carryPacked >> 24) & 0xFFu;

                    const uint w0 = sgTotals[w - 1u][a0 >> 2];
                    const uint w1 = sgTotals[w - 1u][a1 >> 2];
                    const uint w2 = sgTotals[w - 1u][a2 >> 2];
                    const uint w3 = sgTotals[w - 1u][a3 >> 2];

                    const uint r0 = (w0 >> ((a0 & 3u) * 8u)) & 0xFFu;
                    const uint r1 = (w1 >> ((a1 & 3u) * 8u)) & 0xFFu;
                    const uint r2 = (w2 >> ((a2 & 3u) * 8u)) & 0xFFu;
                    const uint r3 = (w3 >> ((a3 & 3u) * 8u)) & 0xFFu;

                    sgCarries[w][p] = pack_quads(r0, r1, r2, r3);
                }
            }

            // totalRow = sgTotals[last] ∘ sgCarries[last]
            const uint last = numActiveWaves - 1u;
            uint totalRow[N_PACK4];
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                const uint carryPacked = sgCarries[last][p];

                const uint a0 = (carryPacked) & 0xFFu;
                const uint a1 = (carryPacked >> 8) & 0xFFu;
                const uint a2 = (carryPacked >> 16) & 0xFFu;
                const uint a3 = (carryPacked >> 24) & 0xFFu;

                const uint w0 = sgTotals[last][a0 >> 2];
                const uint w1 = sgTotals[last][a1 >> 2];
                const uint w2 = sgTotals[last][a2 >> 2];
                const uint w3 = sgTotals[last][a3 >> 2];

                const uint r0 = (w0 >> ((a0 & 3u) * 8u)) & 0xFFu;
                const uint r1 = (w1 >> ((a1 & 3u) * 8u)) & 0xFFu;
                const uint r2 = (w2 >> ((a2 & 3u) * 8u)) & 0xFFu;
                const uint r3 = (w3 >> ((a3 & 3u) * 8u)) & 0xFFu;

                totalRow[p] = pack_quads(r0, r1, r2, r3);
            }

            const uint dstBase = block * N_STATES;
            [unroll]
            for (uint s = 0; s < N_STATES; ++s)
            {
                const uint w = totalRow[s >> 2];
                const uint sh = (s & 3u) * 8u;
                block_summaries[dstBase + s] = (w >> sh) & 0xFFu;
            }
        }
    }
}
