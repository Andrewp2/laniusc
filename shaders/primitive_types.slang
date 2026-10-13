// Primitive identities are shared by checked graphs, portable interfaces and
// machine lowering. Rust constants are generated from the marked declarations.
// Identity is independent of machine width and signedness.
// PRIMITIVE_CONSTANT
public static const uint SCALAR_UNKNOWN = 0u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_UNIT = 1u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_BOOL = 2u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_I32 = 3u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_U32 = 4u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_F32 = 5u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_CHAR = 6u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_STR = 7u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_PTR = 8u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_I64 = 9u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_U64 = 10u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_I8 = 11u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_I16 = 12u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_U8 = 13u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_U16 = 14u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_F64 = 15u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_ISIZE = 16u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_USIZE = 17u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_TYPE_SHIFT = 27u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_TYPE_LINK_MASK = 0x07ffffffu;

public bool scalar_is_known(uint scalar)
{
    return scalar >= SCALAR_UNIT && scalar <= SCALAR_USIZE;
}

public bool scalar_is_signed_integer(uint scalar)
{
    return scalar == SCALAR_I8 || scalar == SCALAR_I16 ||
        scalar == SCALAR_I32 || scalar == SCALAR_I64 || scalar == SCALAR_ISIZE;
}

public bool scalar_is_unsigned_integer(uint scalar)
{
    return scalar == SCALAR_U8 || scalar == SCALAR_U16 ||
        scalar == SCALAR_U32 || scalar == SCALAR_U64 || scalar == SCALAR_USIZE;
}

public bool scalar_is_integer(uint scalar)
{
    return scalar_is_signed_integer(scalar) || scalar_is_unsigned_integer(scalar);
}

public bool scalar_is_float(uint scalar)
{
    return scalar == SCALAR_F32 || scalar == SCALAR_F64;
}

// The initial native target has 64-bit pointer-sized integers. This query
// describes value semantics; array/resource capacities are a separate domain.
public uint scalar_integer_bits(uint scalar)
{
    if (scalar == SCALAR_I8 || scalar == SCALAR_U8) return 8u;
    if (scalar == SCALAR_I16 || scalar == SCALAR_U16) return 16u;
    if (scalar == SCALAR_I32 || scalar == SCALAR_U32) return 32u;
    if (scalar == SCALAR_I64 || scalar == SCALAR_U64 ||
        scalar == SCALAR_ISIZE || scalar == SCALAR_USIZE) return 64u;
    return 0u;
}

public bool scalar_is_wide_integer(uint scalar)
{
    return scalar_integer_bits(scalar) == 64u;
}

public bool scalar_is_narrow_integer(uint scalar)
{
    uint bits = scalar_integer_bits(scalar);
    return bits != 0u && bits < 32u;
}

public bool scalar_is_gpr_value(uint scalar)
{
    return scalar_is_integer(scalar) || scalar == SCALAR_UNIT ||
        scalar == SCALAR_BOOL || scalar == SCALAR_CHAR || scalar == SCALAR_PTR;
}

public bool scalar_uses_64bit_gpr(uint scalar)
{
    return scalar == SCALAR_PTR || scalar_is_wide_integer(scalar);
}

public bool scalar_is_unsigned_value(uint scalar)
{
    return scalar_is_unsigned_integer(scalar) || scalar == SCALAR_BOOL ||
        scalar == SCALAR_CHAR || scalar == SCALAR_PTR;
}
