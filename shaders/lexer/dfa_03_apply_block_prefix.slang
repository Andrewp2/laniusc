// Apply per-block prefix to produce f_final[i] (state after consuming byte i).
// Target: RTX 3090, wave size = 32.
//
// Approach:
// - Preload a 256-byte block into groupshared once.
// - Process in PAIRS of waves: (0,1), (2,3), (4,5), (6,7).
//   The EVEN wave ("owner") handles both its own 32 bytes (A) and its neighbor's 32 bytes (B).
// - **Lane 0** of the owner wave runs the sequential DFA for both A and B and writes all
//   results for those 64 bytes. Other lanes in that wave sit idle. This removes all
//   WaveReadLaneAt() usage and the per-step baton overhead.
// - We keep a single groupshared carry per pair. One CTA sync at the start of each pair
//   iteration makes the previous pair’s carry visible.
//
// Notes:
// * Only wave size 32 is supported.
// * No spin/wait; forward progress safe.
// * `WaveReadLaneAt` is not used (so “active lane” constraint is trivially satisfied).

#define WORKGROUP_SIZE 256
#define WAVE_SIZE 32u
#define MAX_WAVES (WORKGROUP_SIZE / WAVE_SIZE) // 8
#define MAX_PAIRS ((MAX_WAVES + 1u) / 2u)      // 4
#define N_STATES 79

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> next_u8;      // [pack4][byte] -> uint(packed 4x u8)
StructuredBuffer<uint> block_prefix; // N_STATES per block (inclusive scan of blocks)
RWStructuredBuffer<uint> f_final;

groupshared uint gB[WORKGROUP_SIZE];    // block's bytes
groupshared uint gPairCarry[MAX_PAIRS]; // end state after each pair

// δ(s, b): apply one byte to a DFA state (u8 state space).
inline uint apply_byte(uint b, uint s)
{
    const uint pack = s >> 2;                // 4 states per pack
    const uint w = next_u8[pack * 256u + b]; // packed 4×u8
    const uint sh = (s & 3u) * 8u;
    return (w >> sh) & 0xFFu;
}

// Number of active lanes (bytes) in wave `w` for this block.
inline uint wave_len_of(uint block_len, uint w)
{
    const uint offset = w * WAVE_SIZE;
    if (offset >= block_len)
        return 0u;
    const uint rem = block_len - offset;
    return (rem < WAVE_SIZE) ? rem : WAVE_SIZE;
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_03_apply_block_prefix(uint3 tid: SV_GroupThreadID,
                               uint3 /*gid*/: SV_DispatchThreadID,
                               uint3 ggrp: SV_GroupID)
{
    // --- Block geometry (must match dfa_01/02 partitioning) ---
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = (nb < 65535u) ? nb : 65535u;
    const uint block = ggrp.y * groupsX + ggrp.x;
    const uint base = block * WORKGROUP_SIZE;

    const uint tIdx = tid.x;              // 0..255
    const uint lane = WaveGetLaneIndex(); // 0..31
    const uint waveId = tIdx / WAVE_SIZE; // 0..7
    const uint i = base + tIdx;

    const uint block_len = (base < gParams.n)
                               ? ((gParams.n - base) < WORKGROUP_SIZE ? (gParams.n - base) : WORKGROUP_SIZE)
                               : 0u;
    if (block >= nb || block_len == 0u)
        return;

    // Seed from prefix of prior blocks.
    uint carry_state0 = gParams.start_state;
    if (block > 0u)
    {
        const uint prevBase = (block - 1u) * N_STATES;
        carry_state0 = block_prefix[prevBase + carry_state0];
    }

    // Preload bytes into groupshared once.
    uint my_b = 0u;
    if (i < gParams.n)
        my_b = load_byte_at(in_bytes, i);
    gB[tIdx] = my_b;
    GroupMemoryBarrierWithGroupSync(); // gB is now visible to all

    const uint wavesInBlock = (block_len + (WAVE_SIZE - 1u)) / WAVE_SIZE;
    const uint pairsInBlock = (wavesInBlock + 1u) / 2u; // ceil(waves/2)

    // Process pairs sequentially; only the even "owner" wave does work each step.
    for (uint p = 0u; p < pairsInBlock; ++p)
    {
        // Ensure previous pair’s carry is published (and gB was ready for p=0).
        GroupMemoryBarrierWithGroupSync();

        const uint ownerWave = 2u * p; // even wave id
        const bool iAmOwner = (waveId == ownerWave);

        // The two waves covered by this pair.
        const uint wA = ownerWave;
        const uint wB = wA + 1u;

        const uint lenA = wave_len_of(block_len, wA);
        const bool hasB = (wB < wavesInBlock);
        const uint lenB = hasB ? wave_len_of(block_len, wB) : 0u;

        if (iAmOwner)
        {
            // Lane 0 performs the sequential DFA for A then (optionally) B.
            if (lane == 0u)
            {
                // Seed for this pair
                uint s = (p == 0u) ? carry_state0 : gPairCarry[p - 1u];

                // --- Wave A ---
                const uint idxBaseA = base + wA * WAVE_SIZE;
                const uint offA = wA * WAVE_SIZE;
                [loop]
                for (uint k = 0u; k < lenA; ++k)
                {
                    const uint b = gB[offA + k];
                    s = apply_byte(b, s);
                    // idxBaseA + k < gParams.n is guaranteed by lenA
                    f_final[idxBaseA + k] = s;
                }

                // --- Wave B (if present) ---
                if (hasB)
                {
                    const uint idxBaseB = base + wB * WAVE_SIZE;
                    const uint offB = wB * WAVE_SIZE;
                    [loop]
                    for (uint k = 0u; k < lenB; ++k)
                    {
                        const uint b = gB[offB + k];
                        s = apply_byte(b, s);
                        f_final[idxBaseB + k] = s;
                    }
                }

                // Publish end-of-pair state for the next step.
                gPairCarry[p] = s;
            }
        }
        // Non-owner waves participate only in the barriers.
    }
}
