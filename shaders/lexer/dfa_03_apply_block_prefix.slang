// 🤖 Fused DFA apply + boundary finalize + seed-kind packing
// 🤖 Replaces the old dfa_03_apply_block_prefix and absorbs boundary_finalize_and_seed
// 🤖 Writes: flags_packed, tok_types, end_excl_by_i directly (no f_final buffer)

#define WORKGROUP_SIZE 256
#define WAVE_SIZE 32u
#define MAX_WAVES (WORKGROUP_SIZE / WAVE_SIZE) // 8
#define MAX_PAIRS ((MAX_WAVES + 1u) / 2u)      // 4
#define N_STATES 79                            // 🤖 Must match tables

import utils; // 🤖 PF_* bits, load helpers, etc.

struct Params
{
    uint n;           // 🤖 number of input bytes
    uint n_states;    // 🤖 DFA state count (must be 79)
    uint start_state; // 🤖 DFA start state
    // 🤖 skip kinds (White/LineComment/BlockComment/etc.) to compute kept-ness
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
};
ConstantBuffer<Params> gParams;

// 🤖 Inputs
ByteAddressBuffer in_bytes;          // 🤖 input bytes
StructuredBuffer<uint> block_prefix; // 🤖 per-block inclusive prefix (N_STATES per block)
StructuredBuffer<uint> token_map;    // 🤖 token kind per state (INVALID32 => non-accepting)
StructuredBuffer<uint> next_emit;    // 🤖 u16 packed: next_state (low 15) | HIGH_BIT for EMIT

// 🤖 Outputs (replaces f_final usage)
RWStructuredBuffer<uint> flags_packed;  // 🤖 PF_EMIT/PF_EOF/PF_KEEP_* per i
RWStructuredBuffer<uint> tok_types;     // 🤖 pack (eof_kind<<16 | emit_kind) per i (0xFFFF for none)
RWStructuredBuffer<uint> end_excl_by_i; // 🤖 per-i exclusive end if single *kept* boundary

groupshared uint gB[WORKGROUP_SIZE];    // 🤖 block byte cache
groupshared uint gPairCarry[MAX_PAIRS]; // 🤖 end-state after each owner-pair

// 🤖 Compute active length for wave w in this block
inline uint wave_len_of(uint block_len, uint w)
{
    const uint offset = w * WAVE_SIZE;
    if (offset >= block_len)
        return 0u;
    const uint rem = block_len - offset;
    return (rem < WAVE_SIZE) ? rem : WAVE_SIZE;
}

// 🤖 Local helper: skip-check
inline bool is_skip(uint tk)
{
    return (tk == gParams.skip0) || (tk == gParams.skip1) || (tk == gParams.skip2) || (tk == gParams.skip3);
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_03_apply_block_prefix(uint3 tid: SV_GroupThreadID,
                               uint3 /*gid*/: SV_DispatchThreadID,
                               uint3 ggrp: SV_GroupID)
{
    // 🤖 Partitioning matches dfa_01 / dfa_02
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE; // 🤖 block count
    const uint groupsX = (nb < 65535u) ? nb : 65535u;                     // 🤖 2D tiling X
    const uint block = ggrp.y * groupsX + ggrp.x;                         // 🤖 linear block id
    const uint base = block * WORKGROUP_SIZE;                             // 🤖 base index of block

    const uint tIdx = tid.x;              // 🤖 0..255
    const uint lane = WaveGetLaneIndex(); // 🤖 0..31
    const uint waveId = tIdx / WAVE_SIZE; // 🤖 0..7
    const uint i_abs = base + tIdx;       // 🤖 absolute byte index

    const uint block_len = (base < gParams.n)
                               ? ((gParams.n - base) < WORKGROUP_SIZE ? (gParams.n - base) : WORKGROUP_SIZE)
                               : 0u;
    if (block >= nb || block_len == 0u)
        return; // 🤖 nothing to do

    // 🤖 Seed carry state from prior blocks via block_prefix table
    uint carry_state0 = gParams.start_state;
    if (block > 0u)
    {
        const uint prevBase = (block - 1u) * N_STATES;
        carry_state0 = block_prefix[prevBase + carry_state0];
    }

    // 🤖 Preload the block's bytes into shared memory once
    uint b_local = 0u;
    if (i_abs < gParams.n)
        b_local = load_byte_at(in_bytes, i_abs);
    gB[tIdx] = b_local;
    GroupMemoryBarrierWithGroupSync(); // 🤖 make gB visible to the whole CTA

    const uint wavesInBlock = (block_len + (WAVE_SIZE - 1u)) / WAVE_SIZE; // 🤖 1..8
    const uint pairsInBlock = (wavesInBlock + 1u) / 2u;                   // 🤖 ceil(waves/2) => 1..4

    // 🤖 Process pairs (even owner wave handles its 32B and its neighbor’s 32B)
    for (uint p = 0u; p < pairsInBlock; ++p)
    {
        GroupMemoryBarrierWithGroupSync(); // 🤖 ensure previous pair carry is visible

        const uint ownerWave = 2u * p;               // 🤖 even wave id
        const bool iAmOwner = (waveId == ownerWave); // 🤖 owner does the sequential walk on lane 0

        const uint wA = ownerWave;                                // 🤖 first wave in the pair
        const uint wB = wA + 1u;                                  // 🤖 second (optional)
        const uint lenA = wave_len_of(block_len, wA);             // 🤖 bytes for A in this block
        const bool hasB = (wB < wavesInBlock);                    // 🤖 whether B exists
        const uint lenB = hasB ? wave_len_of(block_len, wB) : 0u; // 🤖 bytes for B

        if (iAmOwner && lane == 0u)
        {
            // 🤖 Seed for this pair (either from start or previous pair’s carry)
            uint s_prev = (p == 0u) ? carry_state0 : gPairCarry[p - 1u];

            // 🤖 Walk Wave A bytes sequentially
            const uint baseA = base + wA * WAVE_SIZE; // 🤖 global start idx for A
            const uint offA = wA * WAVE_SIZE;         // 🤖 shared-memory offset for A
            [loop]
            for (uint k = 0u; k < lenA; ++k)
            {
                const uint idx = baseA + k;  // 🤖 absolute i
                const uint b = gB[offA + k]; // 🤖 byte value

                // 🤖 Load (next_state | EMIT bit) from packed u16 table
                const uint packed = load_u16_packed(next_emit, b * N_STATES + s_prev);
                const bool emit_here = is_highest_bit_set(packed);
                const uint s_cur = (packed & 0x7FFFu); // 🤖 next DFA state

                // 🤖 EOF / accept / keep logic
                const bool at_eof = (idx + 1u == gParams.n);
                const uint tk_emit = token_map[s_prev];
                const uint tk_eof = token_map[s_cur];

                const bool valid_emit = (tk_emit != 0xFFFFffffu);
                const bool valid_eof = (tk_eof != 0xFFFFffffu);

                const bool keep_emit = (valid_emit && !is_skip(tk_emit));
                const bool keep_eof = (valid_eof && !is_skip(tk_eof));

                const uint emit16 = (keep_emit && valid_emit) ? (tk_emit & 0xFFFFu) : 0xFFFFu;
                const uint eof16 = (keep_eof && valid_eof) ? (tk_eof & 0xFFFFu) : 0xFFFFu;

                const bool eof_accept = (at_eof && valid_eof);

                // 🤖 Pack flags
                uint f = 0u;
                f |= emit_here ? PF_EMIT : 0u;
                f |= eof_accept ? PF_EOF : 0u;
                f |= keep_emit ? PF_KEEP_EMIT : 0u;
                f |= keep_eof ? PF_KEEP_EOF : 0u;

                // 🤖 Write fused outputs
                flags_packed[idx] = f;
                tok_types[idx] = (eof16 << 16) | emit16;
                end_excl_by_i[idx] = (eof_accept && keep_eof) ? gParams.n : idx;

                s_prev = s_cur; // 🤖 advance DFA
            }

            // 🤖 Walk Wave B bytes (if present)
            if (hasB)
            {
                const uint baseB = base + wB * WAVE_SIZE; // 🤖 global start idx for B
                const uint offB = wB * WAVE_SIZE;         // 🤖 shared-memory offset for B
                [loop]
                for (uint k = 0u; k < lenB; ++k)
                {
                    const uint idx = baseB + k;  // 🤖 absolute i
                    const uint b = gB[offB + k]; // 🤖 byte value

                    const uint packed = load_u16_packed(next_emit, b * N_STATES + s_prev);
                    const bool emit_here = is_highest_bit_set(packed);
                    const uint s_cur = (packed & 0x7FFFu);

                    const bool at_eof = (idx + 1u == gParams.n);
                    const uint tk_emit = token_map[s_prev];
                    const uint tk_eof = token_map[s_cur];

                    const bool valid_emit = (tk_emit != 0xFFFFffffu);
                    const bool valid_eof = (tk_eof != 0xFFFFffffu);

                    const bool keep_emit = (valid_emit && !is_skip(tk_emit));
                    const bool keep_eof = (valid_eof && !is_skip(tk_eof));

                    const uint emit16 = (keep_emit && valid_emit) ? (tk_emit & 0xFFFFu) : 0xFFFFu;
                    const uint eof16 = (keep_eof && valid_eof) ? (tk_eof & 0xFFFFu) : 0xFFFFu;

                    const bool eof_accept = (at_eof && valid_eof);

                    uint f = 0u;
                    f |= emit_here ? PF_EMIT : 0u;
                    f |= eof_accept ? PF_EOF : 0u;
                    f |= keep_emit ? PF_KEEP_EMIT : 0u;
                    f |= keep_eof ? PF_KEEP_EOF : 0u;

                    flags_packed[idx] = f;                                           // 🤖 flags
                    tok_types[idx] = (eof16 << 16) | emit16;                         // 🤖 kind pack
                    end_excl_by_i[idx] = (eof_accept && keep_eof) ? gParams.n : idx; // 🤖 end

                    s_prev = s_cur; // 🤖 advance DFA
                }
            }

            gPairCarry[p] = s_prev; // 🤖 publish pair end-state
        }
        // 🤖 Non-owner threads participate only in barriers
    }
}
