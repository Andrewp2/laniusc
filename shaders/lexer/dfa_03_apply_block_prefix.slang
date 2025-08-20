// Re-run the in-block prefix with the block carry (inclusive prefix of prior blocks).
// Ping–pong version without chunking.

#define WORKGROUP_SIZE 64
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
StructuredBuffer<uint> next_emit;    // 2x u16 per uint (low15=next, high1=emit)
StructuredBuffer<uint> block_prefix; // per-block inclusive prefix vector
RWStructuredBuffer<uint> f_final;

// Two planes
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

    // Load δ_b row into Ping
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

    // In-block inclusive scan (ping–pong)
    uint pingAsSrc = 1u;
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
            [unroll]
            for (uint p = 0; p < N_PACK4; ++p)
            {
                write_pack4_to_dst(pingAsSrc, tid.x, p, read_pack4_from_src(pingAsSrc, tid.x, p));
            }
        }

        GroupMemoryBarrierWithGroupSync();
        pingAsSrc ^= 1u;
    }

    // Apply final in-block prefix to the carry(start)
    if (i < gParams.n)
    {
        const uint srcIsPing = pingAsSrc;
        f_final[i] = read8_from_src(srcIsPing, tid.x, carry_state0);
    }
}
