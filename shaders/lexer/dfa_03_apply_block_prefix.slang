// Re-run the in-block prefix with the block carry (inclusive prefix of prior blocks).
// In-place scan with single shared array (u8 packing).

#define WORKGROUP_SIZE 256
#define N_STATES 79
#define N_PACK4 ((N_STATES + 3) / 4)
#define N_PACK4_STRIDE (N_PACK4 + 1)

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;
StructuredBuffer<uint> next_u8;      // packed 4x u8 next-state per uint, layout: [pack][byte]
StructuredBuffer<uint> block_prefix; // per-block inclusive prefix vector
RWStructuredBuffer<uint> f_final;

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

inline uint read_pack4_from_row(uint row, uint p)
{
    return funcArr[row][p];
}

inline void write_pack4_to_row(uint row, uint p, uint packed)
{
    funcArr[row][p] = packed;
}

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void dfa_03_apply_block_prefix(uint3 tid: SV_GroupThreadID,
                               uint3 gid: SV_DispatchThreadID,
                               uint3 ggrp: SV_GroupID)
{
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = min(nb, 65535u);

    const uint block = ggrp.y * groupsX + ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // Carry is inclusive prefix of previous block:
    uint carry_state0 = gParams.start_state;
    if (block > 0u && block < nb)
    {
        const uint prevBase = (block - 1u) * N_STATES;
        carry_state0 = block_prefix[prevBase + carry_state0];
    }

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

    // In-block inclusive scan (in-place, two barriers per stride)
    for (uint offset = 1u; offset < WORKGROUP_SIZE; offset <<= 1u)
    {
        const bool active = (tid.x >= offset);
        const uint srcRow = tid.x - offset;

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

                write_pack4_to_row(tid.x, p, pack_quads(r0, r1, r2, r3));
            }
        }

        GroupMemoryBarrierWithGroupSync();
    }

    if (i < gParams.n)
    {
        f_final[i] = read8_from_row(tid.x, carry_state0);
    }
}
