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
        (operands.a == X86_LIR_BINARY_SHL_I32 ||
         operands.a == X86_LIR_BINARY_SHR_I32);
}

uint x86_safety_guard_bytes(X86LirCore core, X86LirOperands operands,
                            X86LirLocations locations)
{
    if ((core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE) &&
        core.local_ordinal != 0xffffffffu)
        return x86_move32_to_fixed_bytes(locations.b, 1u) + 20u;
    if (x86_safety_shift(core, operands))
        return x86_move32_to_fixed_bytes(locations.c, 1u) + 17u;
    if (x86_safety_integer_division(core, operands))
    {
        uint bytes = x86_move32_to_fixed_bytes(locations.c, 1u) + 16u;
        if ((operands.metadata & 0xffu) == 3u)
            bytes += x86_move32_to_fixed_bytes(locations.b, 0u) + 24u;
        return bytes;
    }
    return 0u;
}
