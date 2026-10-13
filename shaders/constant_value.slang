// A scalar constant's identity is (scalar, low bits, high bits). Storage rows,
// numeric equality and native width are not substitutes for this identity.
// Floats preserve exact IEEE bits, including signed zero and NaN payloads.
// This contract transports values; it does not evaluate floating expressions.
import primitive_types;
import integer_words;

public bool constant_scalar_is_supported(uint scalar)
{
    return scalar_is_integer(scalar) || scalar == SCALAR_BOOL ||
        scalar == SCALAR_CHAR || scalar_is_float(scalar);
}

public bool constant_value_is_valid(uint3 value)
{
    uint scalar = value.x;
    uint2 bits = value.yz;
    if (scalar_is_integer(scalar))
        return all(bits == integer_words_normalize(bits, scalar_integer_bits(scalar)));
    if (scalar == SCALAR_BOOL) return bits.y == 0u && bits.x <= 1u;
    if (scalar == SCALAR_CHAR)
        return bits.y == 0u && bits.x <= 0x10ffffu &&
            (bits.x < 0xd800u || bits.x > 0xdfffu);
    if (scalar == SCALAR_F32) return bits.y == 0u;
    return scalar == SCALAR_F64;
}

public bool constant_values_equal(uint3 left, uint3 right)
{
    return constant_value_is_valid(left) && constant_value_is_valid(right) && all(left == right);
}

// Check the source magnitude before constructing its declared-width value.
// No limb pattern, including all ones, is reserved as an invalid value.
public bool constant_value_from_integer_magnitude(uint scalar, uint2 magnitude,
    bool negative, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    if (!integer_words_magnitude_fits(magnitude, scalar, negative)) return false;
    uint2 bits = negative ? integer_words_negate(magnitude) : magnitude;
    value = uint3(scalar, integer_words_normalize(bits, scalar_integer_bits(scalar)));
    return true;
}

// Array/resource counts are a separate semantic domain. This projection proves
// integer, nonnegative and u32-representable; each resource then checks its own
// capacity and product limits. A u32::MAX value is not itself invalid.
public bool constant_value_to_count(uint3 value, out uint count)
{
    count = 0u;
    if (!constant_value_is_valid(value) || !scalar_is_integer(value.x) ||
        value.z != 0u || (scalar_is_signed_integer(value.x) &&
            integer_words_negative(value.yz, scalar_integer_bits(value.x)))) return false;
    count = value.y;
    return true;
}

// Array inference converts a checked count to the parameter's declared scalar
// only after proving representability. Ordinary generic arguments use exact
// typed identity and never call this conversion implicitly.
public bool constant_value_from_count(uint count, uint scalar, out uint3 value)
{
    return constant_value_from_integer_magnitude(scalar, uint2(count, 0u), false, value);
}
