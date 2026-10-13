// Pure address sizing; importing it must not declare emitter output buffers.
import codegen.lowering_ir;
import codegen.lir.x86.location_common;

bool x86_index_has_runtime_stride(X86LirCore core)
{ return core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME; }

uint x86_index_address_bytes(X86LirCore core, X86LirOperands operands,
    X86LirLocations locations, uint words)
{
    uint bytes = x86_move64_to_fixed_bytes(locations.a, 0u);
    if (x86_index_has_runtime_stride(core))
        return bytes + ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u
            ? 7u : x86_move64_to_fixed_bytes(locations.a + 2u, 1u)) +
            x86_move32_to_fixed_bytes(locations.b, 2u) + 7u;
    return bytes + x86_move32_to_fixed_bytes(locations.b, 1u) +
        ((operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u ? 4u : 11u);
}

