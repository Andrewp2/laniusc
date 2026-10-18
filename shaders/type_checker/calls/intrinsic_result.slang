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

// The legacy result code of an intrinsic: ptr for the data pointers, the
// i32 slice code for i32_slice_from_raw_parts, unknown for the typed slice
// (its element comes from the caller) and void for the rest.
public uint intrinsic_result_type(uint intrinsic)
{
    if (intrinsic == INTRINSIC_I32_ARRAY_DATA_PTR || intrinsic == INTRINSIC_I32_SLICE_DATA_PTR ||
        intrinsic == INTRINSIC_STRING_DATA_PTR) return 8u;
    if (intrinsic == INTRINSIC_I32_SLICE_FROM_RAW_PARTS) return 128u + 3u;
    return intrinsic == INTRINSIC_TYPED_SLICE_FROM_RAW_PARTS ? 0u : 1u;
}

// The scalar result of an intrinsic call (a code in 2..127), or 0 when its
// result is void or not a scalar.
public uint intrinsic_scalar_result(uint intrinsic)
{
    uint type = intrinsic == INTRINSIC_NONE ? 0u : intrinsic_result_type(intrinsic);
    return type > 1u && type < 128u ? type : 0u;
}
