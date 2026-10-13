import primitive_types;
import codegen.lowering_ir;
import codegen.lir.x86.location_common;

uint x86_safety_exit_bytes() { return 12u; }

bool x86_safety_integer_division(X86LirCore core, X86LirOperands operands)
{
    return core.op == X86_LIR_OP_BINARY &&
        (operands.a == X86_LIR_BINARY_DIV_I32 ||
         operands.a == X86_LIR_BINARY_REM_I32);
}

bool x86_safety_shift(X86LirCore core, X86LirOperands operands)
{
    return core.op == X86_LIR_OP_BINARY &&
        (operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
        (operands.a == X86_LIR_BINARY_SHL_I32 ||
         operands.a == X86_LIR_BINARY_SHR_I32);
}

uint x86_safety_guard_bytes(X86LirCore core, X86LirOperands operands,
                            X86LirLocations locations)
{
    bool rhs_wide = (operands.metadata & X86_LIR_METADATA_RHS_NARROW) == 0u;
    uint type = operands.metadata & 0xffu;
    if ((core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE ||
         core.op == X86_LIR_OP_INDEX_ADDRESS) && core.local_ordinal != 0xffffffffu)
    {
        uint bytes = rhs_wide ? x86_move64_to_fixed_bytes(locations.b, 1u)
            : x86_move32_to_fixed_bytes(locations.b, 1u);
        if (core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
            bytes += ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u
                ? x86_move64_to_fixed_bytes(locations.a, 0u) + 3u
                : x86_move32_to_fixed_bytes(locations.length, 0u)) + (rhs_wide ? 3u : 2u);
        else bytes += rhs_wide ? 8u : 6u;
        return bytes + 14u;
    }
    if (x86_safety_shift(core, operands))
        return (rhs_wide ? x86_move64_to_fixed_bytes(locations.c, 1u)
            : x86_move32_to_fixed_bytes(locations.c, 1u)) + (rhs_wide ? 18u : 17u);
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
