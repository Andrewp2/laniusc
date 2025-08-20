
module utils;

public static const uint HIGH_BIT = 0x8000u;
public static const uint PF_EMIT = 1u << 0;
public static const uint PF_EOF = 1u << 1;
public static const uint PF_KEEP_EMIT = 1u << 2;
public static const uint PF_KEEP_EOF = 1u << 3;

public inline bool is_highest_bit_set(uint value)
{
    return (value & HIGH_BIT) != 0u;
}

public inline uint load_byte_at(ByteAddressBuffer buf, uint i)
{
    uint word = buf.Load(i & ~3u);
    uint shift = (i & 3u) * 8u;
    return (word >> shift) & 0xFFu;
}

public inline uint load_u16_packed(StructuredBuffer<uint> buf, uint idx)
{
    uint w = buf[idx >> 1];
    uint sh = (idx & 1u) * 16u;
    return (w >> sh) & 0xFFFFu;
}

// Load two consecutive u16 values starting at idx (may cross u32 word boundary).
// Returns: low16 = value at idx, high16 = value at idx+1.
public inline uint load_u32_two_u16(StructuredBuffer<uint> buf, uint idx)
{
    const uint w0 = buf[idx >> 1];
    const uint is_odd = idx & 1u;
    if (is_odd == 0u)
    {
        // Both halves live in the same 32-bit word.
        return w0;
    }
    else
    {
        // Crosses boundary: hi16 comes from next word's low16.
        const uint w1 = buf[(idx >> 1) + 1u];
        const uint lo = (w0 >> 16) & 0xFFFFu;
        const uint hi = (w1 & 0xFFFFu) << 16;
        return lo | hi;
    }
}

public inline bool is_last(uint i, uint n)
{
    return (i + 1u == n);
}

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

public inline uint any_end_from_flags(uint f)
{
    return ((f & (PF_EMIT | PF_EOF)) != 0u) ? 1u : 0u;
}

public inline uint kept_any_from_flags(uint f)
{
    uint emit_kept = ((f & PF_EMIT) != 0u && (f & PF_KEEP_EMIT) != 0u) ? 1u : 0u;
    uint eof_kept = ((f & PF_EOF) != 0u && (f & PF_KEEP_EOF) != 0u) ? 1u : 0u;
    return (emit_kept | eof_kept);
}

public inline uint linearize2D(uint x, uint y, uint nx)
{
    return y * nx + x;
}

public inline uint linearize_dispatch_2d_to_1d(uint3 dispatchTid, uint nx)
{
    return dispatchTid.y * nx + dispatchTid.x;
}

public inline uint linearize_group_2d_to_1d(
    uint3 groupID, uint3 groupThreadID,
    uint groupsX, uint tgsX, uint tgsY)
{
    const uint global_x = groupID.x * tgsX + groupThreadID.x;
    const uint global_y = groupID.y * tgsY + groupThreadID.y;
    const uint nx = groupsX * tgsX;
    return global_y * nx + global_x;
}
