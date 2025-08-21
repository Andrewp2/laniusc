// Per-block composition of δ_b functions (each row: N_STATES x u8).
// Output: block_summaries[block] = δ_block for that 256-byte block.
//
// Wave-size fixed at 32 (RTX 3090).
// Strategy:
//   - Half-warp tree reduction uses a compact per-wave groupshared staging slab.
//     Slots are DISJOINT per stage (z=0..3), so we need exactly ONE barrier per stage.
//   - Cross-half compose: lane 16 spills its half-total row to a dedicated slot,
//     then lane 0 composes (half1 ∘ half0). This avoids the high register pressure
//     and extra wave reads from the previous row16[] broadcast path.
//
// Constraints: only this file is edited; must pass fuzz_lex.

#define WORKGROUP_SIZE 256
#define WAVE_SIZE 32u
#define N_STATES 79
#define N_PACK4 ((N_STATES + 3) / 4) // 20
#define N_PACK4_STRIDE (N_PACK4 + 1) // +1 to reduce bank conflicts
#define MAX_WAVES (WORKGROUP_SIZE / WAVE_SIZE)

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

// Per-wave provider slab: per half we need 8+4+2+1 = 15 slots => 30 per wave.
groupshared uint provRows[MAX_WAVES * 30][N_PACK4_STRIDE];

groupshared uint sgTotals[MAX_WAVES][N_PACK4_STRIDE];
groupshared uint sgCarries[MAX_WAVES][N_PACK4_STRIDE];

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

// Stage bases per half so slots are disjoint across z=0..3.
static const uint STAGE_BASE[4] = { 0u, 8u, 12u, 14u };

// slots per half at stage z: 8 >> z   (8,4,2,1)
inline uint provider_slot(uint waveId, uint halfId, uint inHalf, uint z)
{
    const uint slotInHalf = inHalf >> (z + 1u); // pair id within this stage
    const uint halfBase = halfId * 15u + STAGE_BASE[z];
    const uint waveBase = waveId * 30u;
    return waveBase + halfBase + slotInHalf;
}

inline uint compose_pack_from_slot(uint LrowPack, uint slot)
{
    const uint a0 = (LrowPack) & 0xFFu;
    const uint a1 = (LrowPack >> 8) & 0xFFu;
    const uint a2 = (LrowPack >> 16) & 0xFFu;
    const uint a3 = (LrowPack >> 24) & 0xFFu;

    const uint w0 = provRows[slot][a0 >> 2];
    const uint w1 = provRows[slot][a1 >> 2];
    const uint w2 = provRows[slot][a2 >> 2];
    const uint w3 = provRows[slot][a3 >> 2];

    const uint r0 = (w0 >> ((a0 & 3u) * 8u)) & 0xFFu;
    const uint r1 = (w1 >> ((a1 & 3u) * 8u)) & 0xFFu;
    const uint r2 = (w2 >> ((a2 & 3u) * 8u)) & 0xFFu;
    const uint r3 = (w3 >> ((a3 & 3u) * 8u)) & 0xFFu;

    return pack_quads(r0, r1, r2, r3);
}

inline void spill_row(uint slot, uint row[N_PACK4])
{
    [unroll]
    for (uint p = 0; p < N_PACK4; ++p)
    {
        provRows[slot][p] = row[p];
    }
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
    const uint tIdx = tid.x;
    const uint i = base + tIdx;

    const uint block_len = (base < gParams.n) ? min(WORKGROUP_SIZE, gParams.n - base) : 0u;
    if (block >= nb || block_len == 0u)
        return;

    // ---- Wave geometry (fixed wave=32) ----
    const uint lane = WaveGetLaneIndex(); // 0..31
    const uint waveId = tIdx / WAVE_SIZE;
    const uint halfId = (lane >> 4); // 0 or 1
    const uint inHalf = lane & 15u;

    // ---- Load this lane's δ_b row into registers (or identity past end) ----
    uint row[N_PACK4];
    if (tIdx < block_len)
    {
        const uint b = load_byte_at(in_bytes, i);
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            row[p] = next_u8[p * 256u + b];
        }
    }
    else
    {
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            row[p] = identity_pack(p);
        }
    }

    // ---------------- Half-warp tree (z = 0,1,2,3  => d = 1,2,4,8) ----------------
    // One barrier per stage: providers spill -> barrier -> heads read/compose.
    {
        // z = 0 (d=1)
        const uint z0 = 0u;
        const uint d0 = 1u;
        const bool isProv0 = ((inHalf & ((d0 << 1) - 1u)) == d0);
        const bool isHead0 = ((inHalf & ((d0 << 1) - 1u)) == 0u);
        const uint slot0 = provider_slot(waveId, halfId, inHalf, z0);

        if (isProv0)
        {
            spill_row(slot0, row);
        }
        GroupMemoryBarrierWithGroupSync();
        if (isHead0)
        {
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                row[p] = compose_pack_from_slot(row[p], slot0);
            }
        }

        // z = 1 (d=2)
        const uint z1 = 1u;
        const uint d1 = 2u;
        const bool isProv1 = ((inHalf & ((d1 << 1) - 1u)) == d1);
        const bool isHead1 = ((inHalf & ((d1 << 1) - 1u)) == 0u);
        const uint slot1 = provider_slot(waveId, halfId, inHalf, z1);

        if (isProv1)
        {
            spill_row(slot1, row);
        }
        GroupMemoryBarrierWithGroupSync();
        if (isHead1)
        {
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                row[p] = compose_pack_from_slot(row[p], slot1);
            }
        }

        // z = 2 (d=4)
        const uint z2 = 2u;
        const uint d2 = 4u;
        const bool isProv2 = ((inHalf & ((d2 << 1) - 1u)) == d2);
        const bool isHead2 = ((inHalf & ((d2 << 1) - 1u)) == 0u);
        const uint slot2 = provider_slot(waveId, halfId, inHalf, z2);

        if (isProv2)
        {
            spill_row(slot2, row);
        }
        GroupMemoryBarrierWithGroupSync();
        if (isHead2)
        {
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                row[p] = compose_pack_from_slot(row[p], slot2);
            }
        }

        // z = 3 (d=8)
        const uint z3 = 3u;
        const uint d3 = 8u;
        const bool isProv3 = ((inHalf & ((d3 << 1) - 1u)) == d3);
        const bool isHead3 = ((inHalf & ((d3 << 1) - 1u)) == 0u);
        const uint slot3 = provider_slot(waveId, halfId, inHalf, z3);

        if (isProv3)
        {
            spill_row(slot3, row);
        }
        GroupMemoryBarrierWithGroupSync();
        if (isHead3)
        {
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                row[p] = compose_pack_from_slot(row[p], slot3);
            }
        }
    }

    // ---------------- Final cross-half compose (lane 16 spills, lane 0 composes) -------------
    // Reserve the last per-wave slot (index 29) for cross-half staging.
    const uint crossSlot = waveId * 30u + 29u;

    if (lane == 16u)
    {
        spill_row(crossSlot, row);
    }
    GroupMemoryBarrierWithGroupSync();

    if (lane == 0u)
    {
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            row[p] = compose_pack_from_slot(row[p], crossSlot); // (half1 ∘ half0)
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // Lane 0 of each wave now holds the wave total in `row`.
    if (lane == 0u)
    {
        [unroll]
        for (uint p = 0; p < N_PACK4; ++p)
        {
            sgTotals[waveId][p] = row[p];
        }
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
            {
                sgCarries[0][p] = identity_pack(p);
            }

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
