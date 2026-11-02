import primitive_types;
import codegen.lowering_ir;
import codegen.lir.x86.location_common;

bool x86_safety_integer_division(X86LirCore core, X86LirOperands operands)
{
    return core.op == X86_LIR_OP_BINARY &&
        (operands.a == X86_LIR_BINARY_DIV_I32 ||
         operands.a == X86_LIR_BINARY_REM_I32);
}

bool x86_safety_shift(X86LirCore core, X86LirOperands operands)
{
    return core.op == X86_LIR_OP_BINARY &&
        (operands.metadata & (X86_LIR_METADATA_IMMEDIATE |
                              X86_LIR_METADATA_BOUNDED_SHIFT)) == 0u &&
        (operands.a == X86_LIR_BINARY_SHL_I32 ||
         operands.a == X86_LIR_BINARY_SHR_I32);
}

// A bounds guard compares a 32-bit index already in a general register with
// its bound directly (no copy into RCX). The bound is a run-time length in a
// register or a stack slot, or a constant.
bool x86_guard_index_in_place(X86LirCore core, X86LirOperands operands,
                              X86LirLocations locations)
{
    if ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) == 0u ||
        !x86_location_is_register(locations.b) || x86_location_is_xmm(locations.b) ||
        locations.b == X86_LOCATION_INVALID)
        return false;
    if (core.local_ordinal != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME) return true;
    return (operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) == 0u &&
        locations.length != X86_LOCATION_INVALID && !x86_location_is_xmm(locations.length);
}

uint x86_safety_guard_bytes(X86LirCore core, X86LirOperands operands,
                            X86LirLocations locations)
{
    bool rhs_wide = (operands.metadata & X86_LIR_METADATA_RHS_NARROW) == 0u;
    uint type = operands.metadata & 0xffu;
    if ((core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE ||
         core.op == X86_LIR_OP_INDEX_ADDRESS) && core.local_ordinal != 0xffffffffu)
    {
        if (x86_guard_index_in_place(core, operands, locations))
        {
            uint index = x86_location_payload(locations.b);
            uint compare = core.local_ordinal != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME
                ? (index >= 8u ? 7u : 6u)
                : x86_location_is_register(locations.length)
                ? (index >= 8u || x86_location_payload(locations.length) >= 8u ? 3u : 2u)
                : x86_stack32_operand_bytes(x86_location_payload(locations.length), index);
            return compare + 6u; // jae rel32 to the runtime bounds trap
        }
        uint bytes = rhs_wide ? x86_move64_to_fixed_bytes(locations.b, 1u)
            : x86_move32_to_fixed_bytes(locations.b, 1u);
        bool indirect = (operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u;
        if (core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME && !indirect &&
            !rhs_wide && x86_location_is_register(locations.length))
            bytes += x86_location_payload(locations.length) >= 8u ? 3u : 2u;
        else if (core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
            bytes += (indirect
                ? x86_move64_to_fixed_bytes(locations.a, 0u) + 3u
                : x86_move32_to_fixed_bytes(locations.length, 0u)) + (rhs_wide ? 3u : 2u);
        else bytes += rhs_wide ? 8u : 6u;
        return bytes + 6u; // jae rel32 to the runtime bounds trap
    }
    if (x86_safety_shift(core, operands))
        return (rhs_wide ? x86_move64_to_fixed_bytes(locations.c, 1u)
            : x86_move32_to_fixed_bytes(locations.c, 1u)) + (rhs_wide ? 10u : 9u);
    if (x86_safety_integer_division(core, operands))
    {
        bool wide = scalar_is_wide_integer(type);
        uint bytes = (wide ? x86_move64_to_fixed_bytes(locations.c, 1u)
            : x86_move32_to_fixed_bytes(locations.c, 1u)) + (wide ? 17u : 16u);
        if (scalar_is_signed_integer(type))
            bytes += wide ? x86_move64_to_fixed_bytes(locations.b, 0u) + 33u
                : x86_move32_to_fixed_bytes(locations.b, 0u) + 24u;
        return bytes;
    }
    return 0u;
}
