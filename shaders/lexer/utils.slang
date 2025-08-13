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

// Load a 16-bit lane from a packed uint buffer (2 * u16 per uint).
public inline uint load_u16_packed(StructuredBuffer<uint> buf, uint idx)
{
    uint w = buf[idx >> 1];
    uint sh = (idx & 1u) * 16u;
    return (w >> sh) & 0xFFFFu;
}

// Unpack helpers for our packed (low15 = state, high1 = emit) layout.
public inline uint unpack_low15(uint v)
{
    return v & 0x7FFFu;
}
public inline uint unpack_high1(uint v)
{
    return (v >> 15u) & 1u;
}

// Convenience predicates / math
public inline bool is_last(uint i, uint n)
{
    return (i + 1u == n);
}

public inline uint saturating_sub(uint a, uint b)
{
    return (a >= b) ? (a - b) : 0u;
}

// Min/Max that are occasionally handy in kernels
public inline uint umin_u(uint a, uint b)
{
    return (a < b) ? a : b;
}
public inline uint umax_u(uint a, uint b)
{
    return (a > b) ? a : b;
}
