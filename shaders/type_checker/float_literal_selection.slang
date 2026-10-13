// The parser rounds each source spelling independently to binary32 and binary64.
// Consumers select both bits and decode status using the same checked scalar.
// This module performs no floating arithmetic or cross-width conversion.
import hir_records;
import primitive_types;
import constant_value;

public bool selected_float_literal_status(uint packed, uint scalar, out uint status)
{
    status = 0xffffffffu;
    if (scalar != SCALAR_F32 && scalar != SCALAR_F64) return false;
    status = (packed >> (scalar == SCALAR_F64 ? 8u : 0u)) & 255u;
    return true;
}

public bool selected_float_literal_value(HirPayload literal, uint packed,
    uint scalar, bool negative, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    uint status;
    if (literal.a != 27u || !selected_float_literal_status(packed, scalar, status) || status != 0u)
        return false;
    if (scalar == SCALAR_F32)
        value = uint3(scalar, literal.b ^ (negative ? 0x80000000u : 0u), 0u);
    else
        value = uint3(scalar, literal.c, literal.d ^ (negative ? 0x80000000u : 0u));
    return constant_value_is_valid(value);
}
