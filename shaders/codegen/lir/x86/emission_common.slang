import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.location_common;
import codegen.lir.x86.safety;
import gpu_index;

struct Params
{
    uint target_capacity;
    uint token_capacity;
    uint function_capacity;
    uint artifact_capacity;
    uint target_start;
    uint page_capacity;
    uint reserved0;
    uint reserved1;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<X86LirLocations> target_lir_locations;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<SemanticLirString> semantic_lir_strings;
StructuredBuffer<uint> semantic_lir_string_pool_len;
StructuredBuffer<uint> semantic_lir_string_data;
StructuredBuffer<uint> x86_decl_location_by_token;
StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
StructuredBuffer<uint> target_byte_length;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<uint> artifact_bytes;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint ELF_BASE_VADDR = 0x400000u;

void store_byte(uint pos, uint value)
{
    if (pos >= gParams.artifact_capacity) return;
    uint word_i = pos >> 2u;
    uint shift = (pos & 3u) * 8u;
    uint mask = 0xffu << shift;
    uint old_value = artifact_bytes[word_i];
    for (;;)
    {
        uint next = (old_value & ~mask) | ((value & 0xffu) << shift);
        uint prior;
        InterlockedCompareExchange(artifact_bytes[word_i], old_value, next, prior);
        if (prior == old_value) return;
        old_value = prior;
    }
}

void emit_u8(inout uint cursor, uint value) { store_byte(cursor++, value); }
void emit_u32(inout uint cursor, uint value)
{
    for (uint i = 0u; i < 4u; i += 1u) emit_u8(cursor, value >> (i * 8u));
}
void emit_u64(inout uint cursor, uint low, uint high)
{
    emit_u32(cursor, low);
    emit_u32(cursor, high);
}

uint displacement(uint slot) { return 0u - 8u * (slot + 1u); }

void emit_stack_modrm(inout uint cursor, uint register, uint slot)
{
    bool narrow = x86_stack_displacement_bytes(slot) == 1u;
    emit_u8(cursor, (narrow ? 0x40u : 0x80u) |
        ((register & 7u) << 3u) | 5u);
    if (narrow) emit_u8(cursor, displacement(slot));
    else emit_u32(cursor, displacement(slot));
}

void emit_rbp_displacement_modrm(inout uint cursor, uint reg,
                                 uint byte_displacement)
{
    bool narrow = x86_signed_displacement_bytes(byte_displacement) == 1u;
    emit_u8(cursor, (narrow ? 0x40u : 0x80u) |
        ((reg & 7u) << 3u) | 5u);
    if (narrow) emit_u8(cursor, byte_displacement);
    else emit_u32(cursor, byte_displacement);
}

void store_stack_packed_i32(inout uint cursor, uint source, uint base_slot,
                            uint element)
{
    if (source >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, 0x89u);
    emit_rbp_displacement_modrm(cursor, source,
        x86_packed_i32_displacement(base_slot, element));
}

void move32_register(inout uint cursor, uint source, uint destination)
{
    if (source == destination) return;
    uint rex = 0x40u | (source >= 8u ? 4u : 0u) | (destination >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    emit_u8(cursor, 0x89u);
    emit_u8(cursor, 0xc0u | ((source & 7u) << 3u) | (destination & 7u));
}

void move64_register(inout uint cursor, uint source, uint destination)
{
    if (source == destination) return;
    emit_u8(cursor, 0x48u | (source >= 8u ? 4u : 0u) |
        (destination >= 8u ? 1u : 0u));
    emit_u8(cursor, 0x89u);
    emit_u8(cursor, 0xc0u | ((source & 7u) << 3u) | (destination & 7u));
}

void load_stack32(inout uint cursor, uint slot, uint destination)
{
    if (destination >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, 0x8bu);
    emit_stack_modrm(cursor, destination, slot);
}

void store_stack32(inout uint cursor, uint source, uint slot)
{
    if (source >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, 0x89u);
    emit_stack_modrm(cursor, source, slot);
}

void load_stack64(inout uint cursor, uint slot, uint destination)
{
    emit_u8(cursor, 0x48u | (destination >= 8u ? 4u : 0u));
    emit_u8(cursor, 0x8bu);
    emit_stack_modrm(cursor, destination, slot);
}

void store_stack64(inout uint cursor, uint source, uint slot)
{
    emit_u8(cursor, 0x48u | (source >= 8u ? 4u : 0u));
    emit_u8(cursor, 0x89u);
    emit_stack_modrm(cursor, source, slot);
}

void emit_stack_address(inout uint cursor, uint destination, uint slot)
{
    emit_u8(cursor, 0x48u | (destination >= 8u ? 4u : 0u));
    emit_u8(cursor, 0x8du);
    emit_stack_modrm(cursor, destination, slot);
}

void move_location32(inout uint cursor, uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return;
    bool source_register = x86_location_is_register(source);
    bool destination_register = x86_location_is_register(destination);
    if (source_register && destination_register)
        move32_register(cursor, x86_location_payload(source),
            x86_location_payload(destination));
    else if (source_register)
        store_stack32(cursor, x86_location_payload(source),
            x86_location_payload(destination));
    else if (destination_register)
        load_stack32(cursor, x86_location_payload(source),
            x86_location_payload(destination));
    else
    {
        load_stack32(cursor, x86_location_payload(source), 0u);
        store_stack32(cursor, 0u, x86_location_payload(destination));
    }
}

void move_location64(inout uint cursor, uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return;
    bool source_register = x86_location_is_register(source);
    bool destination_register = x86_location_is_register(destination);
    if (source_register && destination_register)
        move64_register(cursor, x86_location_payload(source),
            x86_location_payload(destination));
    else if (source_register)
        store_stack64(cursor, x86_location_payload(source),
            x86_location_payload(destination));
    else if (destination_register)
        load_stack64(cursor, x86_location_payload(source),
            x86_location_payload(destination));
    else
    {
        load_stack64(cursor, x86_location_payload(source), 0u);
        store_stack64(cursor, 0u, x86_location_payload(destination));
    }
}

void emit_imm32_to_location(inout uint cursor, uint value, uint destination)
{
    if (x86_location_is_register(destination))
    {
        uint destination_gpr = x86_location_payload(destination);
        if (value == 0u)
        {
            if (destination_gpr >= 8u) emit_u8(cursor, 0x45u);
            emit_u8(cursor, 0x31u);
            emit_u8(cursor, 0xc0u | ((destination_gpr & 7u) << 3u) |
                (destination_gpr & 7u));
            return;
        }
        if (destination_gpr >= 8u) emit_u8(cursor, 0x41u);
        emit_u8(cursor, 0xb8u + (destination_gpr & 7u));
        emit_u32(cursor, value);
    }
    else
    {
        if (value == 0u)
        { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u); }
        else
        { emit_u8(cursor, 0xb8u); emit_u32(cursor, value); }
        store_stack32(cursor, 0u, x86_location_payload(destination));
    }
}

void emit_binary32_to_register(inout uint cursor, uint operation, uint right,
                               uint destination)
{
    uint destination_gpr = x86_location_payload(destination);
    bool right_register = x86_location_is_register(right);
    uint right_payload = x86_location_payload(right);
    uint rex = 0x40u | (destination_gpr >= 8u ? 4u : 0u) |
        (right_register && right_payload >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    if (operation == X86_LIR_BINARY_MUL_I32)
    {
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, 0xafu);
    }
    else emit_u8(cursor,
        operation == X86_LIR_BINARY_ADD_I32 ? 0x03u :
        operation == X86_LIR_BINARY_SUB_I32 ? 0x2bu :
        operation == X86_LIR_BINARY_BIT_AND_I32 ||
            operation == X86_LIR_BINARY_AND_BOOL ? 0x23u :
        operation == X86_LIR_BINARY_BIT_OR_I32 ||
            operation == X86_LIR_BINARY_OR_BOOL ? 0x0bu : 0x33u);
    if (right_register)
        emit_u8(cursor, 0xc0u | ((destination_gpr & 7u) << 3u) |
            (right_payload & 7u));
    else emit_stack_modrm(cursor, destination_gpr, right_payload);
}

void emit_lea_add32(inout uint cursor, uint left, uint right,
                    uint destination)
{
    uint base = x86_location_payload(left);
    uint index = x86_location_payload(right);
    if ((index & 7u) == 4u)
    {
        uint swap = base;
        base = index;
        index = swap;
    }
    uint destination_gpr = x86_location_payload(destination);
    uint rex = 0x40u | (destination_gpr >= 8u ? 4u : 0u) |
        (index >= 8u ? 2u : 0u) | (base >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    emit_u8(cursor, 0x8du);
    bool displaced_base = (base & 7u) == 5u;
    emit_u8(cursor, (displaced_base ? 0x40u : 0u) |
        ((destination_gpr & 7u) << 3u) | 4u);
    emit_u8(cursor, ((index & 7u) << 3u) | (base & 7u));
    if (displaced_base) emit_u8(cursor, 0u);
}

void emit_lea_scaled32(inout uint cursor, uint source, uint destination,
                       uint scale)
{
    uint source_gpr = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    uint rex = 0x40u | (destination_gpr >= 8u ? 4u : 0u) |
        (source_gpr >= 8u ? 3u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    emit_u8(cursor, 0x8du);
    bool displaced_base = (source_gpr & 7u) == 5u;
    emit_u8(cursor, (displaced_base ? 0x40u : 0u) |
        ((destination_gpr & 7u) << 3u) | 4u);
    emit_u8(cursor, (scale << 6u) |
        ((source_gpr & 7u) << 3u) | (source_gpr & 7u));
    if (displaced_base) emit_u8(cursor, 0u);
}

void emit_imul_immediate32(inout uint cursor, uint immediate, uint source,
                           uint destination)
{
    uint source_payload = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    bool source_register = x86_location_is_register(source);
    uint rex = 0x40u | (destination_gpr >= 8u ? 4u : 0u) |
        (source_register && source_payload >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    bool narrow = x86_immediate_fits_i8(immediate);
    emit_u8(cursor, narrow ? 0x6bu : 0x69u);
    if (source_register)
        emit_u8(cursor, 0xc0u | ((destination_gpr & 7u) << 3u) |
            (source_payload & 7u));
    else emit_stack_modrm(cursor, destination_gpr, source_payload);
    if (narrow) emit_u8(cursor, immediate);
    else emit_u32(cursor, immediate);
}

void emit_lea_displaced32(inout uint cursor, uint displacement,
                          uint source, uint destination)
{
    uint source_gpr = x86_location_payload(source);
    uint destination_gpr = x86_location_payload(destination);
    uint rex = 0x40u | (destination_gpr >= 8u ? 4u : 0u) |
        (source_gpr >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    emit_u8(cursor, 0x8du);
    bool narrow = x86_immediate_fits_i8(displacement);
    bool sib = (source_gpr & 7u) == 4u;
    emit_u8(cursor, (narrow ? 0x40u : 0x80u) |
        ((destination_gpr & 7u) << 3u) |
        (sib ? 4u : source_gpr & 7u));
    if (sib) emit_u8(cursor, 0x24u);
    if (narrow) emit_u8(cursor, displacement);
    else emit_u32(cursor, displacement);
}

void emit_inc_dec32(inout uint cursor, uint destination, bool decrement)
{
    uint destination_gpr = x86_location_payload(destination);
    if (destination_gpr >= 8u) emit_u8(cursor, 0x41u);
    emit_u8(cursor, 0xffu);
    emit_u8(cursor, (decrement ? 0xc8u : 0xc0u) |
        (destination_gpr & 7u));
}

uint move_f32_to_xmm(uint cursor, uint location, uint destination)
{
    if (x86_location_is_xmm(location))
    {
        uint source = x86_location_xmm(location);
        if (source == destination) return cursor;
        emit_u8(cursor, 0xf3u);
        uint rex = 0x40u | (destination >= 8u ? 4u : 0u) |
            (source >= 8u ? 1u : 0u);
        if (rex != 0x40u) emit_u8(cursor, rex);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x10u);
        emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
            (source & 7u));
        return cursor;
    }
    if (x86_location_is_register(location))
    {
        uint source = x86_location_payload(location);
        emit_u8(cursor, 0x66u);
        uint rex = 0x40u | (destination >= 8u ? 4u : 0u) |
            (source >= 8u ? 1u : 0u);
        if (rex != 0x40u) emit_u8(cursor, rex);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x6eu);
        emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
            (source & 7u));
        return cursor;
    }
    emit_u8(cursor, 0xf3u);
    if (destination >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x10u);
    emit_stack_modrm(cursor, destination, x86_location_payload(location));
    return cursor;
}

uint move_f32_from_xmm(uint cursor, uint source, uint location)
{
    if (x86_location_is_xmm(location))
    {
        uint destination = x86_location_xmm(location);
        if (source == destination) return cursor;
        emit_u8(cursor, 0xf3u);
        uint rex = 0x40u | (destination >= 8u ? 4u : 0u) |
            (source >= 8u ? 1u : 0u);
        if (rex != 0x40u) emit_u8(cursor, rex);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x10u);
        emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
            (source & 7u));
        return cursor;
    }
    if (x86_location_is_register(location))
    {
        uint destination = x86_location_payload(location);
        emit_u8(cursor, 0x66u);
        uint rex = 0x40u | (source >= 8u ? 4u : 0u) |
            (destination >= 8u ? 1u : 0u);
        if (rex != 0x40u) emit_u8(cursor, rex);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x7eu);
        emit_u8(cursor, 0xc0u | ((source & 7u) << 3u) |
            (destination & 7u));
        return cursor;
    }
    emit_u8(cursor, 0xf3u);
    if (source >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x11u);
    emit_stack_modrm(cursor, source, x86_location_payload(location));
    return cursor;
}

void move_f32_to_gpr(inout uint cursor, uint location, uint destination)
{
    if (!x86_location_is_xmm(location))
    {
        if (x86_location_is_register(location))
            move32_register(cursor, x86_location_payload(location),
                destination);
        else load_stack32(cursor, x86_location_payload(location), destination);
        return;
    }
    cursor = move_f32_from_xmm(cursor, x86_location_xmm(location),
        X86_LOCATION_REGISTER | destination);
}

void move_f32_from_gpr(inout uint cursor, uint source, uint location)
{
    if (!x86_location_is_xmm(location))
    {
        if (x86_location_is_register(location))
            move32_register(cursor, source, x86_location_payload(location));
        else store_stack32(cursor, source, x86_location_payload(location));
        return;
    }
    cursor = move_f32_to_xmm(cursor, X86_LOCATION_REGISTER | source,
        x86_location_xmm(location));
}

void move_f32_location(inout uint cursor, uint source, uint destination)
{
    if (source == destination && source != X86_LOCATION_INVALID) return;
    if (x86_location_is_xmm(destination))
        cursor = move_f32_to_xmm(
            cursor, source, x86_location_xmm(destination));
    else if (x86_location_is_xmm(source))
        cursor = move_f32_from_xmm(
            cursor, x86_location_xmm(source), destination);
    else move_location32(cursor, source, destination);
}

bool f32_binary_commutative(uint operation)
{
    return operation == X86_LIR_BINARY_ADD_F32 ||
        operation == X86_LIR_BINARY_MUL_F32;
}

void emit_f32_binary_instruction(inout uint cursor, uint operation,
                                 uint destination, uint right)
{
    uint right_xmm = 14u;
    if (x86_location_is_xmm(right))
        right_xmm = x86_location_xmm(right);
    else if (x86_location_is_register(right))
        cursor = move_f32_to_xmm(cursor, right, right_xmm);
    emit_u8(cursor, 0xf3u);
    uint rex = 0x40u | (destination >= 8u ? 4u : 0u) |
        (x86_location_is_xmm(right) && right_xmm >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    emit_u8(cursor, 0x0fu);
    emit_u8(cursor,
        operation == X86_LIR_BINARY_ADD_F32 ? 0x58u :
        operation == X86_LIR_BINARY_SUB_F32 ? 0x5cu :
        operation == X86_LIR_BINARY_MUL_F32 ? 0x59u : 0x5eu);
    if (x86_location_is_xmm(right) || x86_location_is_register(right))
        emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
            (right_xmm & 7u));
    else emit_stack_modrm(cursor, destination, x86_location_payload(right));
}

void emit_f32_binary(inout uint cursor, uint operation, uint left, uint right,
                     uint result)
{
    uint destination = x86_location_is_xmm(result)
        ? x86_location_xmm(result) : 15u;
    bool destination_is_right = x86_location_is_xmm(right) &&
        x86_location_xmm(right) == destination;
    bool destination_is_left = x86_location_is_xmm(left) &&
        x86_location_xmm(left) == destination;
    if (destination_is_right && !destination_is_left &&
        f32_binary_commutative(operation))
    {
        uint swap = left;
        left = right;
        right = swap;
        destination_is_right = false;
    }
    uint compute = destination_is_right && !destination_is_left
        ? 15u : destination;
    cursor = move_f32_to_xmm(cursor, left, compute);
    emit_f32_binary_instruction(cursor, operation, compute, right);
    cursor = move_f32_from_xmm(cursor, compute, result);
}

void emit_f32_compare(inout uint cursor, uint left, uint right)
{
    uint left_xmm = x86_location_is_xmm(left)
        ? x86_location_xmm(left) : 15u;
    cursor = move_f32_to_xmm(cursor, left, left_xmm);
    uint right_xmm = 14u;
    if (x86_location_is_xmm(right))
        right_xmm = x86_location_xmm(right);
    else if (x86_location_is_register(right))
        cursor = move_f32_to_xmm(cursor, right, right_xmm);
    uint rex = 0x40u | (left_xmm >= 8u ? 4u : 0u) |
        (x86_location_is_xmm(right) && right_xmm >= 8u ? 1u : 0u);
    if (rex != 0x40u) emit_u8(cursor, rex);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x2eu);
    if (x86_location_is_xmm(right) || x86_location_is_register(right))
        emit_u8(cursor, 0xc0u | ((left_xmm & 7u) << 3u) |
            (right_xmm & 7u));
    else emit_stack_modrm(cursor, left_xmm, x86_location_payload(right));
}

uint base_frame_slots(TargetLirFunction function, SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK) +
        (semantic_function.result_word_count > 2u ? 1u : 0u);
}

uint hidden_sret_slot(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
}

bool frameless_function(TargetLirFunction function,
                        SemanticLirFunction semantic_function)
{
    // A hidden structure-return pointer needs an addressable frame slot even
    // when ordinary allocation found no spills.
    return (function.flags & X86_TARGET_FUNCTION_FRAMELESS) != 0u &&
        semantic_function.result_word_count <= 2u;
}

bool stackless_caller(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_STACKLESS_CALLER) != 0u &&
        semantic_function.result_word_count <= 2u;
}

uint implicit_footer_bytes(TargetLirFunction function,
                           SemanticLirFunction semantic_function,
                           uint saved_mask)
{
    return frameless_function(function, semantic_function) ? 3u :
        stackless_caller(function, semantic_function) ? 4u :
        4u + x86_saved_gpr_frame_bytes(saved_mask,
            base_frame_slots(function, semantic_function));
}

uint frame_size(TargetLirFunction function, SemanticLirFunction semantic_function,
                uint saved_mask)
{
    uint slots = base_frame_slots(function, semantic_function) +
        x86_saved_gpr_count(saved_mask);
    return ((slots * 8u + 15u) / 16u) * 16u;
}

uint declaration_location(uint declaration_token)
{
    uint location = declaration_token < gParams.token_capacity
        ? x86_decl_location_by_token[declaration_token] : X86_LOCATION_INVALID;
    // Synthetic value-set rows use the function's first spill slot rather
    // than a source declaration. Preserve that explicit lowering convention
    // while real declarations use their allocated homes.
    return location == X86_LOCATION_INVALID ? 0u : location;
}

uint value_slot(uint value_row, TargetLirFunction function)
{
    return x86_location_payload(value_row);
}

void load_value32(inout uint cursor, uint location, uint destination,
                  TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move32_register(cursor, x86_location_payload(location), destination);
    else load_stack32(cursor,
        value_slot(x86_location_payload(location), function), destination);
}

void store_value32(inout uint cursor, uint source, uint location,
                   TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move32_register(cursor, source, x86_location_payload(location));
    else store_stack32(cursor, source,
        value_slot(x86_location_payload(location), function));
}

void load_value64(inout uint cursor, uint location, uint destination,
                  TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move64_register(cursor, x86_location_payload(location), destination);
    else load_stack64(cursor, value_slot(x86_location_payload(location), function), destination);
}

void store_value64(inout uint cursor, uint source, uint location,
                   TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move64_register(cursor, source, x86_location_payload(location));
    else store_stack64(cursor, source, value_slot(x86_location_payload(location), function));
}

void emit_compare_locations32(inout uint cursor, uint left, uint right,
                              TargetLirFunction function)
{
    bool left_register = x86_location_is_register(left);
    bool right_register = x86_location_is_register(right);
    if (!left_register && !right_register)
    {
        load_value32(cursor, left, 0u, function);
        load_value32(cursor, right, 1u, function);
        emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u);
        return;
    }

    uint reg = x86_location_payload(left_register ? left : right);
    uint rm = x86_location_payload(left_register ? right : left);
    uint rex = 0x40u;
    if (left_register && right_register)
    {
        // cmp left, right: opcode 39 encodes left as r/m and right as reg.
        if (x86_location_payload(right) >= 8u) rex |= 4u;
        if (x86_location_payload(left) >= 8u) rex |= 1u;
        if (rex != 0x40u) emit_u8(cursor, rex);
        emit_u8(cursor, 0x39u);
        emit_u8(cursor, 0xc0u |
            ((x86_location_payload(right) & 7u) << 3u) |
            (x86_location_payload(left) & 7u));
        return;
    }

    // With one stack operand, opcode 39 handles stack-left/register-right;
    // opcode 3B preserves the operand order for register-left/stack-right.
    if (reg >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, left_register ? 0x3bu : 0x39u);
    emit_stack_modrm(cursor, reg, value_slot(rm, function));
}

void emit_test_location32(inout uint cursor, uint location,
                          TargetLirFunction function)
{
    if (!x86_location_is_register(location))
    {
        load_value32(cursor, location, 0u, function);
        emit_u8(cursor, 0x85u); emit_u8(cursor, 0xc0u);
        return;
    }
    uint reg = x86_location_payload(location);
    if (reg >= 8u) emit_u8(cursor, 0x45u);
    emit_u8(cursor, 0x85u);
    emit_u8(cursor, 0xc0u | ((reg & 7u) << 3u) | (reg & 7u));
}

void store_declaration64(inout uint cursor, uint source, uint location)
{
    if (x86_location_is_register(location))
        move64_register(cursor, source, x86_location_payload(location));
    else store_stack64(cursor, source, x86_location_payload(location));
}

uint saved_register_for_ordinal(uint ordinal)
{
    static const uint registers[5] = {3u, 12u, 13u, 14u, 15u};
    return registers[min(ordinal, 4u)];
}

void save_registers(inout uint cursor, uint mask, uint first_slot)
{
    uint saved_ordinal = 0u;
    for (uint ordinal = 0u; ordinal < 5u; ordinal += 1u)
    {
        uint physical = saved_register_for_ordinal(ordinal);
        if ((mask & (1u << physical)) == 0u) continue;
        store_stack64(cursor, physical, first_slot + saved_ordinal);
        saved_ordinal += 1u;
    }
}

void restore_registers(inout uint cursor, uint mask, uint first_slot)
{
    uint saved_ordinal = x86_saved_gpr_count(mask);
    for (uint ordinal = 5u; ordinal > 0u; ordinal -= 1u)
    {
        uint physical = saved_register_for_ordinal(ordinal - 1u);
        if ((mask & (1u << physical)) == 0u) continue;
        saved_ordinal -= 1u;
        load_stack64(cursor, first_slot + saved_ordinal, physical);
    }
}

uint param_store_bytes(TargetLirFunction target_function,
                       SemanticLirFunction function, uint hidden_sret)
{
    uint bytes = hidden_sret != 0u
        ? x86_stack64_operand_bytes(hidden_sret_slot(target_function, function)) : 0u;
    uint abi_ordinal = hidden_sret;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        uint width = x86_abi_param_width(param);
        uint destination = declaration_location(param.declaration_id);
        for (uint component = 0u; component < width; component += 1u)
        {
            uint incoming = abi_ordinal + component;
            bytes += incoming < 6u
                ? x86_move64_from_fixed_bytes(x86_abi_argument_register(incoming), destination + component)
                : (frameless_function(target_function, function) ||
                   stackless_caller(target_function, function) ? 8u : 7u) +
                  x86_move64_from_fixed_bytes(0u, destination + component);
        }
        abi_ordinal += width;
    }
    return bytes;
}

uint prologue_bytes(TargetLirFunction target, SemanticLirFunction function, uint saved_mask)
{
    uint hidden = function.result_word_count > 2u ? 1u : 0u;
    uint slots = base_frame_slots(target, function);
    bool frameless = frameless_function(target, function);
    bool stackless = stackless_caller(target, function);
    return (frameless ? 0u : stackless ? 1u :
        4u + (slots + x86_saved_gpr_count(saved_mask) == 0u ? 0u : 7u) +
        x86_saved_gpr_frame_bytes(saved_mask, slots)) +
        param_store_bytes(target, function, hidden);
}
