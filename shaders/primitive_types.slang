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
// The never type `!`: the result of a function that does not return. It has
// no values and no machine width.
// PRIMITIVE_CONSTANT
public static const uint SCALAR_NEVER = 18u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_TYPE_SHIFT = 27u;
// PRIMITIVE_CONSTANT
public static const uint SCALAR_TYPE_LINK_MASK = 0x07ffffffu;

// Scalar classes are bit sets indexed by SCALAR_* identity (every identity is
// below 32). A query is one clamp, shift and mask with no branches, so each of
// the many inlined copies stays a few instructions.
public static const uint SCALAR_SIGNED_INTEGER_SET = (1u << SCALAR_I8) | (1u << SCALAR_I16) |
    (1u << SCALAR_I32) | (1u << SCALAR_I64) | (1u << SCALAR_ISIZE);
public static const uint SCALAR_UNSIGNED_INTEGER_SET = (1u << SCALAR_U8) | (1u << SCALAR_U16) |
    (1u << SCALAR_U32) | (1u << SCALAR_U64) | (1u << SCALAR_USIZE);
public static const uint SCALAR_INTEGER_SET = SCALAR_SIGNED_INTEGER_SET | SCALAR_UNSIGNED_INTEGER_SET;
public static const uint SCALAR_FLOAT_SET = (1u << SCALAR_F32) | (1u << SCALAR_F64);
public static const uint SCALAR_WIDE_INTEGER_SET = (1u << SCALAR_I64) | (1u << SCALAR_U64) |
    (1u << SCALAR_ISIZE) | (1u << SCALAR_USIZE);
public static const uint SCALAR_NARROW_INTEGER_SET = (1u << SCALAR_I8) | (1u << SCALAR_U8) |
    (1u << SCALAR_I16) | (1u << SCALAR_U16);
public static const uint SCALAR_GPR_VALUE_SET = SCALAR_INTEGER_SET | (1u << SCALAR_UNIT) |
    (1u << SCALAR_BOOL) | (1u << SCALAR_CHAR) | (1u << SCALAR_PTR);
public static const uint SCALAR_64BIT_GPR_SET = SCALAR_WIDE_INTEGER_SET | (1u << SCALAR_PTR);
public static const uint SCALAR_UNSIGNED_VALUE_SET = SCALAR_UNSIGNED_INTEGER_SET |
    (1u << SCALAR_BOOL) | (1u << SCALAR_CHAR) | (1u << SCALAR_PTR);
// log2(bits / 8) of each integer identity below 16, two bits per identity.
// isize and usize (16, 17) are 64-bit; non-integers are masked by the caller.
public static const uint SCALAR_INTEGER_WIDTH_CODES = (2u << (2u * SCALAR_I32)) |
    (2u << (2u * SCALAR_U32)) | (3u << (2u * SCALAR_I64)) | (3u << (2u * SCALAR_U64)) |
    (1u << (2u * SCALAR_I16)) | (1u << (2u * SCALAR_U16));

// Bit 31 of every set is clear, so clamping keeps out-of-range ids outside.
// The clamp is a select, not min(): with Slang 2026.2 an inlined min() stops
// dead-call elimination of otherwise unused callers.
[ForceInline]
public bool scalar_in_set(uint scalar, uint set)
{
    return ((set >> select(scalar < 31u, scalar, 31u)) & 1u) != 0u;
}

// A primitive identity that has values: unit through usize. Never has no
// values, so value rules (widths, literals, comparisons) do not apply to it.
[ForceInline]
public bool scalar_is_known(uint scalar)
{
    return (scalar - SCALAR_UNIT) < SCALAR_USIZE;
}

// A checked type reference (tag, payload) to never: scalar tag 1. A value of
// type never does not arrive, so it fits any expected type.
[ForceInline]
public bool type_ref_is_never(uint tag, uint payload)
{
    return tag == 1u && payload == SCALAR_NEVER;
}

// Type-mismatch details for a `-> !` function that can return: a `return`
// statement in it, or a path that reaches the end of its body. The Rust
// diagnostics decode them (gpu_compiler/helpers.rs).
// PRIMITIVE_CONSTANT
public static const uint NEVER_RETURN_STATEMENT = 0x20000001u;
// PRIMITIVE_CONSTANT
public static const uint NEVER_RETURN_FALLS_OFF = 0x20000002u;

// Any primitive identity, never included: canonical IDs and interface leaves.
[ForceInline]
public bool scalar_is_identity(uint scalar)
{
    return (scalar - SCALAR_UNIT) < SCALAR_NEVER;
}

[ForceInline]
public bool scalar_is_signed_integer(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_SIGNED_INTEGER_SET);
}

[ForceInline]
public bool scalar_is_unsigned_integer(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_UNSIGNED_INTEGER_SET);
}

[ForceInline]
public bool scalar_is_integer(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_INTEGER_SET);
}

[ForceInline]
public bool scalar_is_float(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_FLOAT_SET);
}

// The initial native target has 64-bit pointer-sized integers. This query
// describes value semantics; array/resource capacities are a separate domain.
[ForceInline]
public uint scalar_integer_bits(uint scalar)
{
    uint code = select(scalar >= 16u, 3u, (SCALAR_INTEGER_WIDTH_CODES >> ((scalar & 15u) * 2u)) & 3u);
    return select(scalar_is_integer(scalar), 8u << code, 0u);
}

[ForceInline]
public bool scalar_is_wide_integer(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_WIDE_INTEGER_SET);
}

[ForceInline]
public bool scalar_is_narrow_integer(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_NARROW_INTEGER_SET);
}

[ForceInline]
public bool scalar_is_gpr_value(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_GPR_VALUE_SET);
}

[ForceInline]
public bool scalar_uses_64bit_gpr(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_64BIT_GPR_SET);
}

[ForceInline]
public bool scalar_is_unsigned_value(uint scalar)
{
    return scalar_in_set(scalar, SCALAR_UNSIGNED_VALUE_SET);
}
