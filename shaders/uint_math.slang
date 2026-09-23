import glsl;

/// Multiplies two `uint` values and clamps overflow to `0xffffffff`.
///
/// `umulExtended` exposes both halves of the 64-bit product without requiring
/// the Int64 shader capability.
public uint saturating_mul_u32(uint left, uint right)
{
    uint high;
    uint low;
    umulExtended(left, right, high, low);
    return high == 0u ? low : 0xffffffffu;
}

/// Ceiling division without overflowing when the numerator is near UINT_MAX.
public uint ceil_div_u32(uint numerator, uint denominator)
{
    return numerator / denominator + uint(numerator % denominator != 0u);
}
