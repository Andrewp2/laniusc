import glsl;

/// Multiplies two `uint` values and clamps overflow to `0xffffffff`.
///
/// `umulExtended` exposes both halves of the 64-bit product without requiring
/// the Int64 shader capability.
public uint saturating_mul_u32(uint left, uint right)
{
    uint low;
    uint high;
    umulExtended(left, right, low, high);
    return high == 0u ? low : 0xffffffffu;
}
