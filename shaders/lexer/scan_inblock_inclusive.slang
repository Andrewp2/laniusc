// Per-block inclusive scan over δ_b functions represented as N_STATES-entry vectors.
// Writes: block_summaries[block] = composed function for the whole block.
//
// Chunked + packed version:
// - Store two 16-bit next-states per 32-bit uint in groupshared.
// - Perform each Hillis–Steele stride in 4 passes over the packed words to keep
//   per-thread registers ~N_PACK/4 instead of ~N_PACK.
// - Use row-level ping–pong (funcPing -> funcPong) each stride to avoid read/write hazards.

#define WORKGROUP_SIZE 128
#define N_STATES 32                 // OK to raise (e.g., 40)
#define N_PACK ((N_STATES + 1) / 2) // # of uint words per row (2 x 16b per word)
#define CHUNKS 1                    // number of passes per stride
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

ByteAddressBuffer in_bytes;       // byte-addressable input
StructuredBuffer<uint> next_emit; // 2x u16 per uint (low15=next, high1=emit)
RWStructuredBuffer<uint> block_summaries;

// --- new: identical interfaces, just padded backing arrays ---
groupshared uint funcPing[WORKGROUP_SIZE][N_PACK_STRIDE];
groupshared uint funcPong[WORKGROUP_SIZE][N_PACK_STRIDE];

inline uint pack_pair(uint lo16, uint hi16)
{
    return (lo16 & 0xFFFFu) | ((hi16 & 0xFFFFu) << 16);
}

// Read 16-bit lane from selected plane (ping as src if pingAsSrc!=0)
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

// Write packed word to the *destination* plane (opposite of src)
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
void scan_inblock_inclusive(uint3 tid: SV_GroupThreadID,
                            uint3 gid: SV_DispatchThreadID,
                            uint3 ggrp: SV_GroupID)
{
    // --- 2D dispatch linearization ---
    const uint nb = (gParams.n + (WORKGROUP_SIZE - 1u)) / WORKGROUP_SIZE;
    const uint groupsX = (nb < 65535u) ? nb : 65535u; // X groups actually dispatched
    const uint block = ggrp.y * groupsX + ggrp.x;     // linear block index across (x,y)
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    // --- Load δ_b row into funcPing as packed pairs (one 32-bit fetch per pair) ---
    if (i < gParams.n)
    {
        const uint b = load_byte_at(in_bytes, i);
        [unroll]
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;

            const uint word = next_emit[(b * N_STATES + s0) >> 1]; // both lanes at once
            const uint lo = word & 0x7FFFu;
            const uint hi = (word >> 16) & 0x7FFFu;

            funcPing[tid.x][p] = pack_pair(lo, (s1 < N_STATES) ? hi : 0u);
        }
    }
    else
    {
        // Identity for out-of-range lanes
        [unroll]
        for (uint p = 0; p < N_PACK; ++p)
        {
            const uint s0 = (p << 1);
            const uint s1 = s0 + 1u;
            funcPing[tid.x][p] = pack_pair(s0, (s1 < N_STATES) ? s1 : 0u);
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // --- Inclusive scan over rows (functions): C = B ∘ A ---
    uint pingAsSrc = 1u; // start reading from Ping, writing to Pong
    for (uint offset = 1u; offset < WORKGROUP_SIZE; offset <<= 1u)
    {
        const bool active = (tid.x >= offset);
        const uint srcRow = tid.x - offset;

        // Process the row in CHUNKS of packed words to keep register pressure low.
        [unroll]
        for (uint chunk = 0; chunk < CHUNKS; ++chunk)
        {
            const uint p_lo = chunk * PACKS_PER_CHUNK;
            const uint p_hi = min(N_PACK, p_lo + PACKS_PER_CHUNK);

            if (active)
            {
                // -------- newRow = B ∘ A (use one srcRow read per pack) --------
                [unroll]
                for (uint p = p_lo; p < p_hi; ++p)
                {
                    const uint s0 = (p << 1);
                    const uint s1 = s0 + 1u;

                    // One load for both lanes from srcRow:
                    const uint srcPacked = read_pack_from_src(pingAsSrc, srcRow, p);
                    const uint a0 = (srcPacked) & 0xFFFFu;
                    const uint a1 = (srcPacked >> 16) & 0xFFFFu;

                    // Lookup on our own row at indices a0 / a1:
                    const uint r0 = read16_from_src(pingAsSrc, tid.x, a0);
                    const uint r1 = (s1 < N_STATES) ? read16_from_src(pingAsSrc, tid.x, a1) : 0u;

                    write_pack_to_dst(pingAsSrc, tid.x, p, pack_pair(r0, r1));
                }
            }
            else
            {
                // Rows below offset remain unchanged this round: copy through (one read).
                [unroll]
                for (uint p = p_lo; p < p_hi; ++p)
                {
                    write_pack_to_dst(pingAsSrc, tid.x, p, read_pack_from_src(pingAsSrc, tid.x, p));
                }
            }
        }

        GroupMemoryBarrierWithGroupSync(); // ensure DST visible
        pingAsSrc ^= 1u;                   // flip planes (no sync needed for the flip)
    }

    // --- Write block summary from the final SRC plane (after last flip) ---
    if (tid.x == WORKGROUP_SIZE - 1u)
    {
        // Guard against over-dispatch rows (y) past the final nb:
        if (block < nb)
        {
            const uint srcIsPing = pingAsSrc; // plane used as SRC holds the final data
            const uint dstBase = block * N_STATES;
            [unroll]
            for (uint s = 0; s < N_STATES; ++s)
            {
                const uint val = read16_from_src(srcIsPing, tid.x, s);
                block_summaries[dstBase + s] = val;
            }
        }
    }
}
