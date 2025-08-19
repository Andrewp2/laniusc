// Re-run the in-block prefix with the block carry (inclusive prefix of prior blocks).
// Ping–pong version without chunking.

#define WORKGROUP_SIZE 64
#define N_STATES 79
#define N_PACK ((N_STATES + 1) / 2)
#define N_PACK_STRIDE (N_PACK + 1)

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
groupshared uint funcPing[WORKGROUP_SIZE][N_PACK_STRIDE];
groupshared uint funcPong[WORKGROUP_SIZE][N_PACK_STRIDE];

inline uint pack_pair(uint lo16, uint hi16)
{
    return (lo16 & 0xFFFFu) | ((hi16 & 0xFFFFu) << 16);
}

inline uint read16_from_src(uint pingAsSrc, uint row, uint idx)
{
    const uint w = (pingAsSrc != 0) ? funcPing[row][idx >> 1] : funcPong[row][idx >> 1];
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
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;
            const uint ns = gParams.n_states;
            if (s0 < ns)
            {
                const uint idx0 = b * ns + s0;
                const uint lo = load_u16_packed(next_emit, idx0) & 0x7FFFu;
                const uint hi = (s1 < ns) ? (load_u16_packed(next_emit, idx0 + 1u) & 0x7FFFu) : 0u;
                funcPing[tid.x][p] = pack_pair(lo, (s1 < N_STATES) ? hi : 0u);
            }
            else
            {
                funcPing[tid.x][p] = pack_pair(s0, (s1 < N_STATES) ? s1 : 0u);
            }
        }
    }
    else
    {
        [unroll]
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;
            funcPing[tid.x][p] = pack_pair(s0, (s1 < N_STATES) ? s1 : 0u);
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
            for (uint p = 0; p < N_PACK; ++p)
            {
                const uint srcPacked = read_pack_from_src(pingAsSrc, srcRow, p);
                const uint a0 = srcPacked & 0xFFFFu;
                const uint a1 = (srcPacked >> 16) & 0xFFFFu;

                const uint r0 = read16_from_src(pingAsSrc, tid.x, a0);
                const uint r1 = read16_from_src(pingAsSrc, tid.x, a1);

                write_pack_to_dst(pingAsSrc, tid.x, p, pack_pair(r0, r1));
            }
        }
        else
        {
            [unroll]
            for (uint p = 0; p < N_PACK; ++p)
            {
                write_pack_to_dst(pingAsSrc, tid.x, p, read_pack_from_src(pingAsSrc, tid.x, p));
            }
        }

        GroupMemoryBarrierWithGroupSync();
        pingAsSrc ^= 1u;
    }

    // Apply final in-block prefix to the carry(start)
    if (i < gParams.n)
    {
        const uint srcIsPing = pingAsSrc;
        f_final[i] = read16_from_src(srcIsPing, tid.x, carry_state0);
    }
}
