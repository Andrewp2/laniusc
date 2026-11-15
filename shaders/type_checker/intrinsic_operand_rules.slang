// Shared fixed-argument checks for the frontend and retained instances.
// `scalar` is 0 for a non-scalar or unresolved reference; `sequence` means
// an array or slice. The caller owns reference decoding and source spans.
import primitive_types;

public bool intrinsic_fixed_argument_violation(uint intrinsic, uint scalar, bool sequence, out uint detail)
{
    detail = 0u;
    if (scalar == SCALAR_NEVER) return false;
    bool accepted;
    if (intrinsic == 1u) // print
    {
        accepted = scalar == SCALAR_I32 || scalar == SCALAR_I8 || scalar == SCALAR_I16 ||
            scalar == SCALAR_U8 || scalar == SCALAR_U16;
        detail = PRINT_ARGUMENT_TYPE;
    }
    else if (intrinsic >= 12u && intrinsic <= 15u)
    {
        uint expected = intrinsic == 12u ? SCALAR_F64 : intrinsic == 13u ? SCALAR_U64 :
            intrinsic == 14u ? SCALAR_F32 : SCALAR_U32;
        accepted = scalar == expected;
        detail = BIT_CAST_ARGUMENT_TYPE | ((intrinsic - 12u) << 8u);
    }
    else // slice_len / string_len
    {
        accepted = intrinsic == 10u ? scalar == SCALAR_STR : sequence;
        detail = LENGTH_ARGUMENT_TYPE | (intrinsic == 10u ? 0x100u : 0u);
    }
    detail |= scalar;
    return !accepted;
}
