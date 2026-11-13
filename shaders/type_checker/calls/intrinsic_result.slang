// Language intrinsic calls (stdlib/core/mem.lani lists them) and their
// result types. 02c_intrinsics tags the calls and publishes the legacy result
// code; 03e_materialize_return_types publishes scalar results as accepted
// call results, so an intrinsic call is a complete argument value.

public static const uint INTRINSIC_NONE = 0u;
public static const uint INTRINSIC_I32_ARRAY_DATA_PTR = 3u;
public static const uint INTRINSIC_I32_SLICE_FROM_RAW_PARTS = 4u;
public static const uint INTRINSIC_I32_SLICE_DATA_PTR = 5u;
public static const uint INTRINSIC_STRING_DATA_PTR = 6u;
public static const uint INTRINSIC_TYPED_SLICE_FROM_RAW_PARTS = 7u;
public static const uint INTRINSIC_SLICE_STRIDE = 8u;
public static const uint INTRINSIC_SLICE_LEN = 9u;
public static const uint INTRINSIC_STRING_LEN = 10u;
public static const uint INTRINSIC_CALL_PTR = 11u;
// The four bit casts are consecutive: f64_to_bits, f64_from_bits,
// f32_to_bits, f32_from_bits.
public static const uint INTRINSIC_F64_TO_BITS = 12u;
public static const uint INTRINSIC_F64_FROM_BITS = 13u;
public static const uint INTRINSIC_F32_TO_BITS = 14u;
public static const uint INTRINSIC_F32_FROM_BITS = 15u;
public static const uint INTRINSIC_SLICE_FROM_STORAGE = 16u;

// The two intrinsics that build a slice of the element type their receiving
// context names: `slice_from_raw_parts` and `slice_from_storage`.
public bool intrinsic_typed_view(uint intrinsic)
{
    return intrinsic == INTRINSIC_TYPED_SLICE_FROM_RAW_PARTS ||
        intrinsic == INTRINSIC_SLICE_FROM_STORAGE;
}

public bool intrinsic_is_bit_cast(uint intrinsic)
{
    return intrinsic >= INTRINSIC_F64_TO_BITS && intrinsic <= INTRINSIC_F32_FROM_BITS;
}

// The scalar a bit cast takes: the float for `*_to_bits`, the unsigned
// integer of the same width for `*_from_bits`.
public uint bit_cast_argument_type(uint intrinsic)
{
    return intrinsic == INTRINSIC_F64_TO_BITS ? 15u :
        intrinsic == INTRINSIC_F64_FROM_BITS ? 10u :
        intrinsic == INTRINSIC_F32_TO_BITS ? 5u : 4u;
}

// The legacy result code of an intrinsic: ptr for the data pointers, the
// i32 slice code for i32_slice_from_raw_parts, isize for slice_stride,
// usize for slice_len and string_len, the other type of the pair for a bit
// cast (u64 and f64, u32 and f32),
// unknown for the two typed views (their element comes from the caller) and void
// for the rest.
public uint intrinsic_result_type(uint intrinsic)
{
    if (intrinsic == INTRINSIC_I32_ARRAY_DATA_PTR || intrinsic == INTRINSIC_I32_SLICE_DATA_PTR ||
        intrinsic == INTRINSIC_STRING_DATA_PTR) return 8u;
    if (intrinsic == INTRINSIC_I32_SLICE_FROM_RAW_PARTS) return 128u + 3u;
    if (intrinsic == INTRINSIC_SLICE_STRIDE) return 16u;
    if (intrinsic == INTRINSIC_SLICE_LEN || intrinsic == INTRINSIC_STRING_LEN) return 17u;
    if (intrinsic_is_bit_cast(intrinsic))
        return bit_cast_argument_type(intrinsic ^ 1u);
    return intrinsic_typed_view(intrinsic) ? 0u : 1u;
}

// The scalar result of an intrinsic call (a code in 2..127), or 0 when its
// result is void or not a scalar.
public uint intrinsic_scalar_result(uint intrinsic)
{
    uint type = intrinsic == INTRINSIC_NONE ? 0u : intrinsic_result_type(intrinsic);
    return type > 1u && type < 128u ? type : 0u;
}
