// Full integer values represented as (low32, high32). These compiler helpers
// require only ordinary 32-bit GPU arithmetic; native values still occupy one
// 64-bit machine word. Narrow values have zero unused bits, not sign-fill bits.
import primitive_types;

public bool integer_words_zero(uint2 value) { return all(value == uint2(0u, 0u)); }
public bool integer_words_less(uint2 left, uint2 right)
{
    return left.y < right.y || (left.y == right.y && left.x < right.x);
}

public uint2 integer_words_add(uint2 left, uint2 right)
{
    uint low = left.x + right.x;
    return uint2(low, left.y + right.y + uint(low < left.x));
}

public uint2 integer_words_sub(uint2 left, uint2 right)
{
    return uint2(left.x - right.x, left.y - right.y - uint(left.x < right.x));
}

public uint2 integer_words_negate(uint2 value)
{
    return integer_words_add(~value, uint2(1u, 0u));
}

public uint2 integer_words_multiply(uint2 left, uint2 right)
{
    uint a0 = left.x & 0xffffu;
    uint a1 = left.x >> 16u;
    uint b0 = right.x & 0xffffu;
    uint b1 = right.x >> 16u;
    uint p0 = a0 * b0;
    uint p1 = a1 * b0 + (p0 >> 16u);
    uint p2 = a0 * b1 + (p1 & 0xffffu);
    uint high = a1 * b1 + (p1 >> 16u) + (p2 >> 16u);
    return uint2((p2 << 16u) | (p0 & 0xffffu),
        high + left.x * right.y + left.y * right.x);
}

public uint2 integer_words_shift_left(uint2 value, uint amount)
{
    if (amount == 0u) return value;
    if (amount >= 64u) return uint2(0u, 0u);
    if (amount >= 32u) return uint2(0u, value.x << (amount - 32u));
    return uint2(value.x << amount, (value.y << amount) | (value.x >> (32u - amount)));
}

public uint2 integer_words_shift_right(uint2 value, uint amount)
{
    if (amount == 0u) return value;
    if (amount >= 64u) return uint2(0u, 0u);
    if (amount >= 32u) return uint2(value.y >> (amount - 32u), 0u);
    return uint2((value.x >> amount) | (value.y << (32u - amount)), value.y >> amount);
}

public uint2 integer_words_mask(uint bits)
{
    if (bits >= 64u) return uint2(0xffffffffu, 0xffffffffu);
    if (bits >= 32u) return uint2(0xffffffffu,
        bits == 32u ? 0u : (1u << (bits - 32u)) - 1u);
    return uint2(bits == 0u ? 0u : (1u << bits) - 1u, 0u);
}

public uint2 integer_words_normalize(uint2 value, uint bits)
{
    return value & integer_words_mask(bits);
}

public bool integer_words_negative(uint2 value, uint bits)
{
    if (bits == 0u || bits > 64u) return false;
    return bits > 32u ? (value.y & (1u << (bits - 33u))) != 0u
        : (value.x & (1u << (bits - 1u))) != 0u;
}

public uint2 integer_words_sign_extend(uint2 value, uint bits)
{
    uint2 mask = integer_words_mask(bits);
    return integer_words_negative(value, bits) ? value | ~mask : value & mask;
}

public uint2 integer_words_cast(uint2 value, uint source_scalar, uint target_scalar)
{
    uint source_bits = scalar_integer_bits(source_scalar);
    uint target_bits = scalar_integer_bits(target_scalar);
    value = scalar_is_signed_integer(source_scalar)
        ? integer_words_sign_extend(value, source_bits)
        : integer_words_normalize(value, source_bits);
    return integer_words_normalize(value, target_bits);
}

public bool integer_words_less_signed(uint2 left, uint2 right, uint bits)
{
    left = integer_words_normalize(left, bits);
    right = integer_words_normalize(right, bits);
    bool left_negative = integer_words_negative(left, bits);
    bool right_negative = integer_words_negative(right, bits);
    return left_negative != right_negative ? left_negative : integer_words_less(left, right);
}

public uint2 integer_words_arithmetic_shift_right(uint2 value, uint amount, uint bits)
{
    value = integer_words_sign_extend(value, bits);
    if (amount == 0u) return integer_words_normalize(value, bits);
    if (amount >= bits || bits == 0u) return uint2(0u, 0u);
    uint2 shifted = integer_words_shift_right(value, amount);
    if ((value.y & 0x80000000u) != 0u)
        shifted |= ~integer_words_mask(64u - amount);
    return integer_words_normalize(shifted, bits);
}

// Every intermediate is bounded: each 16-bit product plus carry fits u32.
// Leading zeros do not consume a synthetic digit budget.
public bool integer_words_append_decimal(uint2 value, uint digit, out uint2 result)
{
    result = uint2(0u, 0u);
    uint2 limit = uint2(0x99999999u, 0x19999999u);
    if (digit > 9u || integer_words_less(limit, value) ||
        (all(value == limit) && digit > 5u)) return false;
    uint low_half = (value.x & 0xffffu) * 10u + digit;
    uint high_half = (value.x >> 16u) * 10u + (low_half >> 16u);
    result.x = (high_half << 16u) | (low_half & 0xffffu);
    result.y = value.y * 10u + (high_half >> 16u);
    return true;
}

public bool integer_words_magnitude_fits(uint2 magnitude, uint scalar, bool negative)
{
    uint bits = scalar_integer_bits(scalar);
    if (bits == 0u) return false;
    if (negative && !scalar_is_signed_integer(scalar)) return integer_words_zero(magnitude);
    uint2 limit = integer_words_mask(bits);
    if (scalar_is_signed_integer(scalar))
    {
        limit = integer_words_shift_left(uint2(1u, 0u), bits - 1u);
        if (!negative) limit = integer_words_sub(limit, uint2(1u, 0u));
    }
    return !integer_words_less(limit, magnitude);
}

public bool integer_words_divide_unsigned(uint2 numerator, uint2 denominator,
    out uint2 quotient, out uint2 remainder)
{
    quotient = uint2(0u, 0u); remainder = uint2(0u, 0u);
    if (integer_words_zero(denominator)) return false;
    for (uint step = 0u; step < 64u; step++)
    {
        uint bit = 63u - step;
        uint incoming = bit >= 32u ? (numerator.y >> (bit - 32u)) & 1u
            : (numerator.x >> bit) & 1u;
        bool overflow = (remainder.y & 0x80000000u) != 0u;
        remainder = integer_words_shift_left(remainder, 1u);
        remainder.x |= incoming;
        if (overflow || !integer_words_less(remainder, denominator))
        {
            remainder = integer_words_sub(remainder, denominator);
            if (bit >= 32u) quotient.y |= 1u << (bit - 32u);
            else quotient.x |= 1u << bit;
        }
    }
    return true;
}

// Returns the established arithmetic failure exit, or zero on success.
public uint integer_words_divide(uint2 left, uint2 right, uint scalar,
    out uint2 quotient, out uint2 remainder)
{
    quotient = uint2(0u, 0u); remainder = uint2(0u, 0u);
    uint bits = scalar_integer_bits(scalar);
    if (bits == 0u) return 1u;
    left = integer_words_normalize(left, bits);
    right = integer_words_normalize(right, bits);
    if (integer_words_zero(right)) return 103u;
    bool signed_integer = scalar_is_signed_integer(scalar);
    bool left_negative = signed_integer && integer_words_negative(left, bits);
    bool right_negative = signed_integer && integer_words_negative(right, bits);
    if (left_negative && all(left == integer_words_shift_left(uint2(1u, 0u), bits - 1u)) &&
        all(right == integer_words_mask(bits))) return 104u;
    uint2 numerator = left_negative
        ? integer_words_normalize(integer_words_negate(left), bits) : left;
    uint2 denominator = right_negative
        ? integer_words_normalize(integer_words_negate(right), bits) : right;
    if (!integer_words_divide_unsigned(numerator, denominator, quotient, remainder)) return 103u;
    if (left_negative != right_negative) quotient = integer_words_negate(quotient);
    if (left_negative) remainder = integer_words_negate(remainder);
    quotient = integer_words_normalize(quotient, bits);
    remainder = integer_words_normalize(remainder, bits);
    return 0u;
}
