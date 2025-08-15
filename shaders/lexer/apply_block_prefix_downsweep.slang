// Re-run the in-block prefix with the block carry (inclusive prefix of prior blocks).
// Packed/chunked version using row-level ping–pong to avoid read/write hazards.

#define WORKGROUP_SIZE 128
#define N_STATES 32
#define N_PACK ((N_STATES + 1) / 2) // two 16-bit lanes per packed uint
#define CHUNKS 1
#define PACKS_PER_CHUNK ((N_PACK + CHUNKS - 1) / CHUNKS)
#define N_PACK_STRIDE (N_PACK + 1)

import utils;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

ByteAddressBuffer in_bytes;          // byte-addressable input
StructuredBuffer<uint> next_emit;    // 2x u16 per uint (low15=next, high1=emit)
StructuredBuffer<uint> block_prefix; // per-block inclusive prefix vector
RWStructuredBuffer<uint> f_final;

// --- new: identical interfaces, just padded backing arrays ---
groupshared uint funcPing[WORKGROUP_SIZE][N_PACK_STRIDE];
groupshared uint funcPong[WORKGROUP_SIZE][N_PACK_STRIDE];

inline uint pack_pair(uint lo16, uint hi16)
{
    return (lo16 & 0xFFFFu) | ((hi16 & 0xFFFFu) << 16);
}

// Read a 16-bit lane from the *source* plane (ping if pingAsSrc!=0)
inline uint read16_from_src(uint pingAsSrc, uint row, uint idx)
{
    const uint w = pingAsSrc != 0 ? funcPing[row][idx >> 1] : funcPong[row][idx >> 1];
    return ((idx & 1u) != 0u) ? ((w >> 16) & 0xFFFFu) : (w & 0xFFFFu);
}

// Read a packed word from the *source* plane
inline uint read_pack_from_src(uint pingAsSrc, uint row, uint p)
{
    return (pingAsSrc != 0) ? funcPing[row][p] : funcPong[row][p];
}

// Write a packed word into the *destination* plane (opposite of src)
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
void apply_block_prefix_downsweep(uint3 tid: SV_GroupThreadID,
                                  uint3 gid: SV_DispatchThreadID,
                                  uint3 ggrp: SV_GroupID)
{
    // --- 2D dispatch linearization ---
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = (nb < 65535u) ? nb : 65535u;
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

    // --- Load δ_b row into funcPing (packed pairs, one 32-bit fetch per pair) ---
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
        // identity for out-of-range lanes
        [unroll]
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;
            funcPing[tid.x][p] = pack_pair(s0, (s1 < N_STATES) ? s1 : 0u);
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // --- Inclusive scan of functions across rows: C = B ∘ A ---
    uint pingAsSrc = 1u; // read from Ping, write to Pong
    for (uint offset = 1u; offset < WORKGROUP_SIZE; offset <<= 1u)
    {
        const bool active = (tid.x >= offset);
        const uint srcRow = tid.x - offset;

        [unroll]
        for (uint chunk = 0; chunk < CHUNKS; ++chunk)
        {
            const uint p_lo = chunk * PACKS_PER_CHUNK;
            const uint p_hi = min(N_PACK, p_lo + PACKS_PER_CHUNK);

            if (active)
            {
                // -------- newRow = B ∘ A (one srcRow read per pack) --------
                [unroll]
                for (uint p = p_lo; p < p_hi; ++p)
                {
                    const uint s0 = (p << 1);
                    const uint s1 = s0 + 1u;

                    const uint srcPacked = read_pack_from_src(pingAsSrc, srcRow, p);
                    const uint a0 = (srcPacked) & 0xFFFFu;
                    const uint a1 = (srcPacked >> 16) & 0xFFFFu;

                    const uint r0 = read16_from_src(pingAsSrc, tid.x, a0);

                    uint r1 = 0u;
                    if (s1 < N_STATES)
                    {
                        r1 = read16_from_src(pingAsSrc, tid.x, a1);
                    }

                    write_pack_to_dst(pingAsSrc, tid.x, p, pack_pair(r0, r1));
                }
            }
            else
            {
                // Copy-through for rows below the offset this round (one read).
                [unroll]
                for (uint p = p_lo; p < p_hi; ++p)
                {
                    write_pack_to_dst(pingAsSrc, tid.x, p, read_pack_from_src(pingAsSrc, tid.x, p));
                }
            }
        }

        GroupMemoryBarrierWithGroupSync();
        pingAsSrc ^= 1u; // local flip is enough
        // (no second barrier needed)
    }

    // --- Apply final in-block prefix to the carry(start) and write out ---
    if (i < gParams.n)
    {
        const uint srcIsPing = pingAsSrc; // plane currently holding final data
        f_final[i] = read16_from_src(srcIsPing, tid.x, carry_state0);
    }
}
