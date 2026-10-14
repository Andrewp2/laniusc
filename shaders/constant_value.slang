// A scalar constant's identity is (scalar, low bits, high bits). Storage rows,
// numeric equality and native width are not substitutes for this identity.
// Floats preserve exact IEEE bits, including signed zero and NaN payloads.
// This contract transports values; it does not evaluate floating expressions.
import primitive_types;
import integer_words;

[ForceInline]
public bool constant_scalar_is_supported(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_INTEGER_SET | SCALAR_FLOAT_SET |
        (1u << SCALAR_BOOL) | (1u << SCALAR_CHAR));
}

// The scalar classes are disjoint, so each clause decides its own class and
// the clauses combine without branching. Integer widths are 8, 16, 32 or 64
// (zero for every other scalar), so only a 64-bit value may use the high word.
// Chars exclude 0xd800..0xdfff.
public bool constant_value_is_valid(uint3 value)
{
    uint scalar = value.x;
    uint2 bits = value.yz;
    bool high_zero = bits.y == 0u;
    uint width = scalar_integer_bits(scalar);
    uint low_mask = select(width >= 32u, 0xffffffffu, (1u << (width & 31u)) - 1u);
    bool integer_ok = (width != 0u) & ((bits.x & ~low_mask) == 0u) & (high_zero | (width == 64u));
    bool bool_ok = (scalar == SCALAR_BOOL) & high_zero & (bits.x <= 1u);
    bool char_ok = (scalar == SCALAR_CHAR) & high_zero & (bits.x <= 0x10ffffu) &
        ((bits.x - 0xd800u) >= 0x800u);
    bool float_ok = ((scalar == SCALAR_F32) & high_zero) | (scalar == SCALAR_F64);
    return integer_ok | bool_ok | char_ok | float_ok;
}

[ForceInline]
public bool constant_values_equal(uint3 left, uint3 right)
{
    return constant_value_is_valid(left) & constant_value_is_valid(right) & all(left == right);
}

// Check the source magnitude before constructing its declared-width value.
// No limb pattern, including all ones, is reserved as an invalid value.
public bool constant_value_from_integer_magnitude(uint scalar, uint2 magnitude,
    bool negative, out uint3 value)
{
    bool fits = integer_words_magnitude_fits(magnitude, scalar, negative);
    uint2 bits = integer_words_normalize(
        integer_words_select(negative, integer_words_negate(magnitude), magnitude),
        scalar_integer_bits(scalar));
    value = select(bool3(fits, fits, fits), uint3(scalar, bits), uint3(0u, 0u, 0u));
    return fits;
}

// Array/resource counts are a separate semantic domain. This projection proves
// integer, nonnegative and u32-representable; each resource then checks its own
// capacity and product limits. A u32::MAX value is not itself invalid.
public bool constant_value_to_count(uint3 value, out uint count)
{
    bool negative = scalar_is_signed_integer(value.x) &
        integer_words_negative(value.yz, scalar_integer_bits(value.x));
    bool valid = constant_value_is_valid(value) & scalar_is_integer(value.x) &
        (value.z == 0u) & !negative;
    count = select(valid, value.y, 0u);
    return valid;
}

// Array inference converts a checked count to the parameter's declared scalar
// only after proving representability. Ordinary generic arguments use exact
// typed identity and never call this conversion implicitly.
// Equal to constant_value_from_integer_magnitude(scalar, uint2(count, 0u),
// false, value): a nonnegative u32 fits below 2^bits (unsigned) or
// 2^(bits-1) (signed), and normalization of a fitting count is the identity.
public bool constant_value_from_count(uint count, uint scalar, out uint3 value)
{
    uint bits = scalar_integer_bits(scalar);
    uint value_bits = bits - uint(scalar_is_signed_integer(scalar));
    bool fits = (bits != 0u) & ((value_bits >= 32u) | ((count >> (value_bits & 31u)) == 0u));
    value = select(bool3(fits, fits, fits), uint3(scalar, count, 0u), uint3(0u, 0u, 0u));
    return fits;
}
