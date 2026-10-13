import primitive_types;
import codegen.lir.x86.emission_common;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;

// RAX is the native first-word destination; RDX is the first-word source.
// This exact 50-byte sequence supports self assignment and overlapping views.
void emit_place_memmove(inout uint cursor, uint words)
{
    if (words == 0u) return;
    emit_u8(cursor, 0x57u); emit_u8(cursor, 0x56u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x39u); emit_u8(cursor, 0xd0u);
    emit_u8(cursor, 0x76u); emit_u8(cursor, 18u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0xc7u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0xd6u);
    emit_u8(cursor, 0xb9u); emit_u32(cursor, words);
    emit_u8(cursor, 0xfdu);
    emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x48u); emit_u8(cursor, 0xa5u);
    emit_u8(cursor, 0xfcu);
    emit_u8(cursor, 0xebu); emit_u8(cursor, 23u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du); emit_u8(cursor, 0xb8u);
    emit_u32(cursor, 0u - (words - 1u) * 8u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du); emit_u8(cursor, 0xb2u);
    emit_u32(cursor, 0u - (words - 1u) * 8u);
    emit_u8(cursor, 0xb9u); emit_u32(cursor, words);
    emit_u8(cursor, 0xfcu);
    emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x48u); emit_u8(cursor, 0xa5u);
    emit_u8(cursor, 0x5eu); emit_u8(cursor, 0x5fu);
}

void emit_place_load(inout uint cursor, X86LirOperands operands,
    X86LirLocations locations, TargetLirFunction function)
{
    bool aggregate = (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
    uint descriptor = (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u ? 3u :
        (operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u ? 2u : 0u;
    if (aggregate)
    {
        // A value read owns its snapshot; the address operation owns the cell.
        load_value64(cursor, locations.a, 2u, function);
        emit_stack_address(cursor, 0u, x86_location_payload(locations.result) + 1u);
        store_value64(cursor, 0u, locations.result, function);
        emit_place_memmove(cursor, operands.c);
    }
    else if (descriptor != 0u)
    {
        load_value64(cursor, locations.a, 0u, function);
        for (uint word = 0u; word < descriptor; word++)
        {
            if (word != 1u) emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x88u);
            emit_u32(cursor, 0u - word * 8u);
            if (word == 1u) store_value32(cursor, 1u, locations.result + word, function);
            else store_value64(cursor, 1u, locations.result + word, function);
        }
    }
    else
    {
        load_value64(cursor, locations.a, 0u, function);
        bool wide = scalar_uses_64bit_gpr(operands.metadata & 0xffu) ||
            x86_scalar_f64(operands.metadata);
        if (wide) emit_u8(cursor, 0x48u);
        emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x00u);
        if (x86_scalar_float(operands.metadata)) move_float_from_gpr(cursor, 0u, locations.result, x86_scalar_f64(operands.metadata));
        else if (wide) store_value64(cursor, 0u, locations.result, function);
        else store_value32(cursor, 0u, locations.result, function);
    }
}

void emit_place_store(inout uint cursor, X86LirOperands operands,
    X86LirLocations locations, TargetLirFunction function)
{
    bool aggregate = (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
    uint descriptor = (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u ? 3u :
        (operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u ? 2u : 0u;
    load_value64(cursor, locations.a, 0u, function);
    if (aggregate || (operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
    {
        load_value64(cursor, locations.b, 2u, function);
        if ((operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
        {
            for (uint word = 0u; word < operands.c; word++)
            {
                emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x8au);
                emit_u32(cursor, word * 4u);
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
                emit_u32(cursor, 0u - word * 8u);
            }
        }
        else emit_place_memmove(cursor, descriptor != 0u ? descriptor : operands.c);
    }
    else if (descriptor != 0u)
    {
        for (uint word = 0u; word < descriptor; word++)
        {
            if (word == 1u) load_value32(cursor, locations.b + word, 1u, function);
            else load_value64(cursor, locations.b + word, 1u, function);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
            emit_u32(cursor, 0u - word * 8u);
        }
    }
    else
    {
        bool wide = scalar_uses_64bit_gpr(operands.metadata & 0xffu) ||
            x86_scalar_f64(operands.metadata);
        if (x86_scalar_float(operands.metadata)) move_float_to_gpr(cursor, locations.b, 1u, x86_scalar_f64(operands.metadata));
        else if (wide) load_value64(cursor, locations.b, 1u, function);
        else load_value32(cursor, locations.b, 1u, function);
        if (wide) emit_u8(cursor, 0x48u);
        emit_u8(cursor, 0x89u); emit_u8(cursor, 0x08u);
    }
}
