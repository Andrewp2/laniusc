// shaders/lexer/utils.slang
// Small helpers used across multiple shaders.

module utils;

// Public constants / bit helpers
public static const uint HIGH_BIT = 0x8000u; // top bit for our 16-bit packed values
public static const uint PF_EMIT = 1u << 0;
public static const uint PF_EOF = 1u << 1;
public static const uint PF_KEEP_EMIT = 1u << 2;
public static const uint PF_KEEP_EOF = 1u << 3;

// Returns true if the highest (15th) bit is set in a 16-bit payload.
public inline bool is_highest_bit_set(uint value)
{
    return (value & HIGH_BIT) != 0u;
}

// Load a single byte from a ByteAddressBuffer at index `i`.
// NOTE: declare bindings per-kernel; this is just a helper.
public inline uint load_byte_at(ByteAddressBuffer buf, uint i)
{
    uint word = buf.Load(i & ~3u); // 4-byte aligned address
    uint shift = (i & 3u) * 8u;
    return (word >> shift) & 0xFFu;
}

// Load a 16-bit lane from a packed uint buffer (2 * u16 per uint).
public inline uint load_u16_packed(StructuredBuffer<uint> buf, uint idx)
{
    uint w = buf[idx >> 1];
    uint sh = (idx & 1u) * 16u;
    return (w >> sh) & 0xFFFFu;
}

// Convenience predicates / math
public inline bool is_last(uint i, uint n)
{
    return (i + 1u == n);
}

// seeds_from_flags: returns (all_seed, kept_seed) as uint2
public inline uint2 seeds_from_flags(uint f)
{
    uint emit = (f & PF_EMIT) != 0u ? 1u : 0u;
    uint eof = (f & PF_EOF) != 0u ? 1u : 0u;

    uint keep_emit = (f & PF_KEEP_EMIT) != 0u ? 1u : 0u;
    uint keep_eof = (f & PF_KEEP_EOF) != 0u ? 1u : 0u;

    uint all_seed = emit + eof;
    uint keep_seed = emit * keep_emit + eof * keep_eof;
    return uint2(all_seed, keep_seed);
}

// any_end_from_flags: 0/1 “any boundary at i”
public inline uint any_end_from_flags(uint f)
{
    return ((f & (PF_EMIT | PF_EOF)) != 0u) ? 1u : 0u;
}

// kept_any_from_flags: 0/1 “any *kept* boundary at i”
public inline uint kept_any_from_flags(uint f)
{
    const uint mask = (PF_EMIT | PF_KEEP_EMIT) | (PF_EOF | PF_KEEP_EOF);
    // (EMIT & KEEP_EMIT) | (EOF & KEEP_EOF)
    uint emit_kept = ((f & PF_EMIT) != 0u && (f & PF_KEEP_EMIT) != 0u) ? 1u : 0u;
    uint eof_kept = ((f & PF_EOF) != 0u && (f & PF_KEEP_EOF) != 0u) ? 1u : 0u;
    return (emit_kept | eof_kept);
}

// --- 2D → 1D helpers -------------------------------------------------------
// Row-major flattening: i = y * nx + x
// NOTE: `nx` must be the total number of *global threads* in X
//       (= dispatch_groups_x * numthreads_x).
public inline uint linearize2D(uint x, uint y, uint nx)
{
    return y * nx + x;
}

// Variant using SV_DispatchThreadID directly.
public inline uint linearize_dispatch_2d_to_1d(uint3 dispatchTid, uint nx)
{
    return dispatchTid.y * nx + dispatchTid.x;
}

// Variant when you only have group/local IDs. You must pass
//   - groupsX : number of dispatched workgroups in X
//   - tgsX/Y  : [numthreads(x, y, ...)] used by the kernel
public inline uint linearize_group_2d_to_1d(
    uint3 groupID, uint3 groupThreadID,
    uint groupsX, uint tgsX, uint tgsY)
{
    const uint global_x = groupID.x * tgsX + groupThreadID.x;
    const uint global_y = groupID.y * tgsY + groupThreadID.y;
    const uint nx = groupsX * tgsX;
    return global_y * nx + global_x;
}
// ---------------------------------------------------------------------------

