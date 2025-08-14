// shaders/lexer/utils.slang
// Small helpers used across multiple shaders.

module utils;

// Public constants / bit helpers
public static const uint HIGH_BIT = 0x8000u; // top bit for our 16-bit packed values

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
