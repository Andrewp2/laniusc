import codegen.lir.x86.index_address_layout;
import codegen.lowering_ir;
// Indexing owns one address calculation for loads, stores, and value copies.
// A runtime view carries its stride; fixed arrays retain their checked place.
import codegen.lir.x86.emission_common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.storage_layout;

// Returns the element address in RAX; RCX and RDX are scratch registers.
void emit_index_address(inout uint cursor, X86LirCore core, X86LirOperands operands,
    X86LirLocations locations, TargetLirFunction function, uint words)
{
    load_value64(cursor, locations.a, 0u, function);
    if (x86_index_has_runtime_stride(core))
    {
        if ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0xf0u); // mov rcx, [rax-16]: signed byte stride
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x00u);
        }
        else load_value64(cursor, locations.a + 2u, 1u, function);
        load_value32(cursor, locations.b, 2u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xafu); emit_u8(cursor, 0xd1u);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x01u); emit_u8(cursor, 0xd0u);
    }
    else
    {
        load_value32(cursor, locations.b, 1u, function);
        if ((operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du); emit_u8(cursor, 0x04u); emit_u8(cursor, 0x88u);
        }
        else
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x69u); emit_u8(cursor, 0xc9u);
            emit_u32(cursor, 0u - words * 8u);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du); emit_u8(cursor, 0x04u); emit_u8(cursor, 0x08u);
        }
    }
}
