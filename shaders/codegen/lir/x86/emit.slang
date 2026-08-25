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

void emit_prologue(inout uint cursor, TargetLirFunction function,
                   SemanticLirFunction semantic_function, uint saved_mask)
{
    bool frameless = frameless_function(function, semantic_function);
    bool stackless = stackless_caller(function, semantic_function);
    if (stackless)
        // SysV function entry is eight bytes away from call alignment. The
        // paired pop uses RCX so a return value already in RAX survives.
        emit_u8(cursor, 0x50u);
    else if (!frameless)
    {
        emit_u8(cursor, 0x55u);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0xe5u);
        uint bytes = frame_size(function, semantic_function, saved_mask);
        if (bytes != 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x81u); emit_u8(cursor, 0xecu);
            emit_u32(cursor, bytes);
        }
        uint first_saved_slot = base_frame_slots(function, semantic_function);
        save_registers(cursor, saved_mask, first_saved_slot);
    }
    uint sret_shift = semantic_function.result_word_count > 2u ? 1u : 0u;
    if (sret_shift != 0u)
        store_stack64(cursor, x86_abi_argument_register(0u),
            hidden_sret_slot(function, semantic_function));
    // Materialize incoming arguments from right to left. Leaf functions may
    // keep early parameters in R8/R9, which are also the fifth and sixth
    // SysV argument registers; saving the high arguments first prevents the
    // destination of parameter zero or one from destroying them.
    for (uint cursor_ordinal = semantic_function.param_count;
         cursor_ordinal > 0u; cursor_ordinal -= 1u)
    {
        uint ordinal = cursor_ordinal - 1u;
        SemanticLirParam param = semantic_lir_params[semantic_function.param_start + ordinal];
        uint abi_ordinal = sret_shift;
        for (uint prior = 0u; prior < ordinal; prior += 1u)
            abi_ordinal += x86_abi_type_width(
                semantic_lir_params[semantic_function.param_start + prior].type_id);
        uint width = x86_abi_type_width(param.type_id);
        if (abi_ordinal + width > 6u) break;
        uint destination = declaration_location(param.declaration_id);
        store_declaration64(cursor, x86_abi_argument_register(abi_ordinal), destination);
        if (width == 2u)
            store_declaration64(cursor, x86_abi_argument_register(abi_ordinal + 1u),
                destination + 1u);
    }
}

void emit_footer(inout uint cursor, TargetLirFunction function,
                 SemanticLirFunction semantic_function, uint saved_mask)
{
    emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u);
    if (stackless_caller(function, semantic_function))
        emit_u8(cursor, 0x59u);
    else if (!frameless_function(function, semantic_function))
    {
        restore_registers(cursor, saved_mask,
            base_frame_slots(function, semantic_function));
        emit_u8(cursor, 0xc9u);
    }
    emit_u8(cursor, 0xc3u);
}

uint setcc_opcode(uint predicate)
{
    if (predicate == 0u) return 0x94u;
    if (predicate == 1u) return 0x95u;
    if (predicate == 2u) return 0x9cu;
    if (predicate == 3u) return 0x9fu;
    if (predicate == 4u) return 0x9eu;
    return 0x9du;
}

uint integer_setcc_opcode(uint predicate, uint type_id)
{
    // u32 and char use the carry-based unsigned condition codes. Equality is
    // representation-independent and therefore shared with signed i32.
    bool is_unsigned = type_id == 4u || type_id == 6u ||
        type_id == SEMANTIC_LIR_TY_POINTER;
    if (!is_unsigned || predicate <= 1u) return setcc_opcode(predicate);
    if (predicate == 2u) return 0x92u;
    if (predicate == 3u) return 0x97u;
    if (predicate == 4u) return 0x96u;
    return 0x93u;
}

uint float_setcc_opcode(uint predicate)
{
    if (predicate == 0u) return 0x94u;
    if (predicate == 1u) return 0x95u;
    if (predicate == 2u) return 0x92u;
    if (predicate == 3u) return 0x97u;
    if (predicate == 4u) return 0x96u;
    return 0x93u;
}

void emit_boolean_result(inout uint cursor, uint opcode, uint location,
                         TargetLirFunction function)
{
    if (x86_location_is_register(location))
    {
        uint destination = x86_location_payload(location);
        if (destination >= 8u) emit_u8(cursor, 0x41u);
        else if (destination >= 4u) emit_u8(cursor, 0x40u);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, opcode);
        emit_u8(cursor, 0xc0u | (destination & 7u));
        if (destination >= 8u) emit_u8(cursor, 0x45u);
        else if (destination >= 4u) emit_u8(cursor, 0x40u);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u);
        emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
            (destination & 7u));
        return;
    }
    emit_u8(cursor, 0x0fu); emit_u8(cursor, opcode); emit_u8(cursor, 0xc0u);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u); emit_u8(cursor, 0xc0u);
    store_value32(cursor, 0u, location, function);
}

uint integer_false_jcc_opcode(uint predicate, uint type_id)
{
    return (integer_setcc_opcode(predicate, type_id) ^ 1u) - 0x10u;
}

uint float_false_jcc_opcode(uint predicate)
{
    return (float_setcc_opcode(predicate) ^ 1u) - 0x10u;
}

uint integer_cmovcc_opcode(uint predicate, uint type_id)
{
    return integer_setcc_opcode(predicate, type_id) - 0x50u;
}

void emit_compare32_immediate(inout uint cursor, uint immediate,
                              uint source_location)
{
    bool source_register = x86_location_is_register(source_location);
    uint source = x86_location_payload(source_location);
    if (immediate == 0u && source_register)
    {
        if (source >= 8u) emit_u8(cursor, 0x45u);
        emit_u8(cursor, 0x85u);
        emit_u8(cursor, 0xc0u | ((source & 7u) << 3u) | (source & 7u));
        return;
    }
    bool narrow = x86_immediate_fits_i8(immediate);
    if (source_register && source >= 8u) emit_u8(cursor, 0x41u);
    if (narrow)
    {
        emit_u8(cursor, 0x83u);
        if (source_register) emit_u8(cursor, 0xf8u | (source & 7u));
        else emit_stack_modrm(cursor, 7u, source);
        emit_u8(cursor, immediate);
    }
    else
    {
        emit_u8(cursor, 0x81u);
        if (source_register) emit_u8(cursor, 0xf8u | (source & 7u));
        else emit_stack_modrm(cursor, 7u, source);
        emit_u32(cursor, immediate);
    }
}

void emit_instruction(inout uint cursor, X86LirCore core, X86LirOperands operands,
                      X86LirLocations locations,
                      TargetLirFunction function, SemanticLirFunction semantic_function,
                      X86ArtifactLayout layout, uint saved_mask)
{
    uint result_slot = value_slot(locations.result, function);
    if (core.op == X86_LIR_OP_IMM_I32)
    {
        if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
        {
            if (operands.a == 0u)
            { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u); }
            else
            { emit_u8(cursor, 0xb8u); emit_u32(cursor, operands.a); }
            move_f32_from_gpr(cursor, 0u, locations.result);
        }
        else
            // A 32-bit immediate write zero-extends to the full GPR, so the
            // same direct form is valid for integers and pointer constants.
            emit_imm32_to_location(cursor, operands.a, locations.result);
    }
    else if (core.op == X86_LIR_OP_ALIAS)
    {
        uint component = (operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u
            ? operands.c : 0u;
        uint source = declaration_location(operands.a) + component;
        if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_location(cursor, source, locations.result);
        else if (x86_alias_uses_64_bits(operands.metadata))
            move_location64(cursor, source, locations.result);
        else move_location32(cursor, source, locations.result);
    }
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        bool aggregate_reference =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        if (aggregate_reference)
        {
            uint first_word_slot = value_slot(locations.result, function) + 1u;
            emit_stack_address(cursor, 0u, first_word_slot);
            store_declaration64(cursor, 0u, declaration_location(operands.a));
        }
        else if ((operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u)
        {
            uint destination = declaration_location(operands.a);
            move_location64(cursor, locations.b, destination);
            move_location32(cursor, locations.c, destination + 1u);
        }
        else if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_location(cursor, locations.b,
                declaration_location(operands.a));
        else if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
            move_location64(cursor, locations.b,
                declaration_location(operands.a));
        else
            move_location32(cursor, locations.b,
                declaration_location(operands.a));
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_ADDR)
    {
        uint first_element_slot = value_slot(locations.result, function) + 1u;
        emit_stack_address(cursor, 0u, first_element_slot);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_INIT)
    {
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        {
            emit_u8(cursor, 0xb8u);
            emit_u32(cursor, operands.a);
        }
        else if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_to_gpr(cursor, locations.a, 0u);
        else load_value64(cursor, locations.a, 0u, function);
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x80u);
            emit_u32(cursor, 0u - operands.b * 8u);
        }
        store_value64(cursor, 0u, locations.c, function);
    }
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value32(cursor, locations.b, 1u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xd9u);
        bool aggregate = (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        if (aggregate)
        {
            // The aggregate pointer addresses descending stack words. Scale
            // the negated element index by the homogeneous element width,
            // then return the element address for subsequent member loads.
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x69u); emit_u8(cursor, 0xc9u);
            emit_u32(cursor, operands.c);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du);
        }
        else
        {
            if ((operands.metadata & 0xffu) != X86_LIR_TY_FLOAT)
                emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0x8bu);
        }
        emit_u8(cursor, 0x04u); emit_u8(cursor, 0xc8u);
        if (!aggregate &&
            (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_from_gpr(cursor, 0u, locations.result);
        else store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
    {
        load_value64(cursor, locations.a, 0u, function);
        bool aggregate =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool f32 = !aggregate &&
            (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT;
        if (!f32) emit_u8(cursor, 0x48u);
        emit_u8(cursor, aggregate ? 0x8du : 0x8bu);
        emit_u8(cursor, 0x80u);
        emit_u32(cursor, 0u - operands.b * 8u);
        if (f32) move_f32_from_gpr(cursor, 0u, locations.result);
        else store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value32(cursor, locations.b, 1u, function);
        if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_to_gpr(cursor, locations.c, 2u);
        else load_value32(cursor, locations.c, 2u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xd9u);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u);
        emit_u8(cursor, 0x14u); emit_u8(cursor, 0xc8u);
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_to_gpr(cursor, locations.c, 1u);
        else load_value32(cursor, locations.c, 1u, function);
        uint stride = operands.metadata >> 24u;
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
        emit_u32(cursor, 0u - operands.b * stride);
    }
    else if (core.op == X86_LIR_OP_BINARY)
    {
        if (x86_const_pow2_binary(operands.a))
        {
            uint divisor = operands.c;
            if (operands.a == X86_LIR_BINARY_DIV_CONST_POW2_I32 &&
                divisor == 1u)
            {
                move_location32(cursor, locations.b, locations.result);
                return;
            }
            if (operands.a == X86_LIR_BINARY_REM_CONST_POW2_I32 &&
                divisor == 1u)
            {
                emit_imm32_to_location(cursor, 0u, locations.result);
                return;
            }
            uint shift = x86_power_of_two_shift(divisor);
            bool is_unsigned = (operands.metadata & 0xffu) == 4u ||
                (operands.metadata & 0xffu) == 6u;
            bool direct = x86_location_is_register(locations.result);
            uint destination = direct
                ? x86_location_payload(locations.result) : 0u;
            if (direct)
                move_location32(cursor, locations.b, locations.result);
            else
                load_value32(cursor, locations.b, 0u, function);
            if (is_unsigned)
            {
                if (operands.a == X86_LIR_BINARY_DIV_CONST_POW2_I32)
                {
                    if (direct && destination >= 8u) emit_u8(cursor, 0x41u);
                    emit_u8(cursor, 0xc1u);
                    emit_u8(cursor, 0xe8u | (destination & 7u));
                    emit_u8(cursor, shift);
                }
                else
                {
                    if (direct)
                    {
                        uint immediate = divisor - 1u;
                        if (destination >= 8u) emit_u8(cursor, 0x41u);
                        emit_u8(cursor, x86_immediate_fits_i8(immediate)
                            ? 0x83u : 0x81u);
                        emit_u8(cursor, 0xe0u | (destination & 7u));
                        if (x86_immediate_fits_i8(immediate))
                            emit_u8(cursor, immediate);
                        else emit_u32(cursor, immediate);
                    }
                    else { emit_u8(cursor, 0x25u); emit_u32(cursor, divisor - 1u); }
                }
            }
            else
            {
                // Signed division truncates toward zero. LLVM describes the
                // power-of-two expansion as SRA + SRL + ADD + SRA; remainder
                // uses the same sign correction before applying the mask.
                if (direct) move32_register(cursor, destination, 2u);
                else { emit_u8(cursor, 0x89u); emit_u8(cursor, 0xc2u); }
                emit_u8(cursor, 0xc1u); emit_u8(cursor, 0xfau);
                emit_u8(cursor, 31u); // sar edx, 31
                emit_u8(cursor, 0xc1u); emit_u8(cursor, 0xeau);
                emit_u8(cursor, 32u - shift); // shr edx, 32 - shift
                if (direct && destination >= 8u) emit_u8(cursor, 0x41u);
                emit_u8(cursor, 0x01u);
                emit_u8(cursor, 0xd0u | (destination & 7u));
                if (operands.a == X86_LIR_BINARY_DIV_CONST_POW2_I32)
                {
                    if (direct && destination >= 8u) emit_u8(cursor, 0x41u);
                    emit_u8(cursor, 0xc1u);
                    emit_u8(cursor, 0xf8u | (destination & 7u));
                    emit_u8(cursor, shift); // sar eax, shift
                }
                else
                {
                    uint immediate = divisor - 1u;
                    if (direct)
                    {
                        if (destination >= 8u) emit_u8(cursor, 0x41u);
                        emit_u8(cursor, x86_immediate_fits_i8(immediate)
                            ? 0x83u : 0x81u);
                        emit_u8(cursor, 0xe0u | (destination & 7u));
                        if (x86_immediate_fits_i8(immediate))
                            emit_u8(cursor, immediate);
                        else emit_u32(cursor, immediate);
                    }
                    else { emit_u8(cursor, 0x25u); emit_u32(cursor, immediate); }
                    if (direct && destination >= 8u) emit_u8(cursor, 0x41u);
                    emit_u8(cursor, 0x29u);
                    emit_u8(cursor, 0xd0u | (destination & 7u));
                }
            }
            if (!direct)
                store_value32(cursor, 0u, locations.result, function);
            return;
        }
        if (x86_const_signed_binary(operands.a))
        {
            uint divisor = operands.c;
            X86SignedDivisionMagic magic =
                x86_signed_division_magic(divisor);
            // EAX/ECX/EDX are reserved from allocation. Materialize the
            // numerator directly in ECX, avoiding the former EAX-to-ECX copy,
            // then sign-extend it for the 64-bit magic multiply.
            move_location32(cursor, locations.b, X86_LOCATION_REGISTER | 1u);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x63u);
            emit_u8(cursor, 0xc1u); // movsxd rax, ecx
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x69u);
            emit_u8(cursor, 0xc0u); emit_u32(cursor, magic.multiplier);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0xc1u);
            emit_u8(cursor, 0xe8u); emit_u8(cursor, 32u); // shr rax, 32
            if (magic.add_numerator)
            {
                emit_u8(cursor, 0x01u); emit_u8(cursor, 0xc8u); // add eax, ecx
            }
            if (magic.shift != 0u)
            {
                emit_u8(cursor, 0xc1u); emit_u8(cursor, 0xf8u);
                emit_u8(cursor, magic.shift); // sar eax, shift
            }
            emit_u8(cursor, 0x89u); emit_u8(cursor, 0xc2u); // mov edx, eax
            emit_u8(cursor, 0xc1u); emit_u8(cursor, 0xeau);
            emit_u8(cursor, 31u); // shr edx, 31
            emit_u8(cursor, 0x01u); emit_u8(cursor, 0xd0u); // add eax, edx
            if (operands.a == X86_LIR_BINARY_REM_CONST_I32)
            {
                emit_u8(cursor, 0x69u); emit_u8(cursor, 0xd0u);
                emit_u32(cursor, divisor); // imul edx, edx, divisor
                emit_u8(cursor, 0x29u); emit_u8(cursor, 0xd1u); // sub ecx, edx
                move_location32(cursor, X86_LOCATION_REGISTER | 1u,
                    locations.result);
            }
            else store_value32(cursor, 0u, locations.result, function);
            return;
        }
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        {
            uint immediate = operands.c;
            if (x86_binary_immediate_identity(operands.a, immediate))
            {
                move_location32(cursor, locations.b, locations.result);
                return;
            }
            bool direct = x86_location_is_register(locations.result);
            uint compute_result = direct
                ? locations.result : X86_LOCATION_REGISTER;
            uint lea_scale;
            if (x86_multiply_immediate_lea_scale(operands.a, immediate,
                    locations.b, compute_result, lea_scale))
            {
                emit_lea_scaled32(cursor, locations.b, compute_result,
                    lea_scale);
                if (!direct)
                    store_value32(cursor, 0u, locations.result, function);
                return;
            }
            uint displacement;
            if (x86_add_sub_immediate_lea(operands.a, immediate,
                    locations.b, compute_result, displacement))
            {
                emit_lea_displaced32(cursor, displacement, locations.b,
                    compute_result);
                if (!direct)
                    store_value32(cursor, 0u, locations.result, function);
                return;
            }
            bool decrement;
            if (x86_binary_immediate_inc_dec(operands.a, immediate,
                    locations.b, locations.result, decrement))
            {
                emit_inc_dec32(cursor, locations.result, decrement);
                return;
            }
            uint destination = direct
                ? x86_location_payload(locations.result) : 0u;
            uint multiply_shift;
            bool shift_multiply = x86_multiply_immediate_shift(
                operands.a, immediate, multiply_shift);
            bool negate_multiply = x86_multiply_immediate_negate(
                operands.a, immediate);
            if (operands.a == X86_LIR_BINARY_MUL_I32 &&
                !shift_multiply && !negate_multiply)
            {
                emit_imul_immediate32(cursor, immediate, locations.b,
                    compute_result);
                if (!direct)
                    store_value32(cursor, 0u, locations.result, function);
                return;
            }
            if (direct)
                move_location32(cursor, locations.b, locations.result);
            else
                load_value32(cursor, locations.b, 0u, function);
            if (operands.a == X86_LIR_BINARY_SHL_I32 ||
                operands.a == X86_LIR_BINARY_SHR_I32 || shift_multiply)
            {
                if (destination >= 8u) emit_u8(cursor, 0x41u);
                emit_u8(cursor, 0xc1u);
                emit_u8(cursor,
                    (operands.a == X86_LIR_BINARY_SHL_I32 || shift_multiply
                        ? 0xe0u :
                    (operands.metadata & 0xffu) == 4u ||
                    (operands.metadata & 0xffu) == 6u ? 0xe8u : 0xf8u) |
                    (destination & 7u));
                emit_u8(cursor, shift_multiply ? multiply_shift : immediate);
            }
            else if (negate_multiply)
            {
                if (destination >= 8u) emit_u8(cursor, 0x41u);
                emit_u8(cursor, 0xf7u);
                emit_u8(cursor, 0xd8u | (destination & 7u));
            }
            else if (operands.a == X86_LIR_BINARY_MUL_I32)
            {
                bool narrow = x86_immediate_fits_i8(immediate);
                if (destination >= 8u) emit_u8(cursor, 0x45u);
                emit_u8(cursor, narrow ? 0x6bu : 0x69u);
                emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
                    (destination & 7u));
                if (narrow) emit_u8(cursor, immediate);
                else emit_u32(cursor, immediate);
            }
            else
            {
                bool narrow = x86_immediate_fits_i8(immediate);
                if (narrow)
                {
                    uint extension =
                        operands.a == X86_LIR_BINARY_ADD_I32 ? 0u :
                        operands.a == X86_LIR_BINARY_SUB_I32 ? 5u :
                        operands.a == X86_LIR_BINARY_BIT_AND_I32 ||
                        operands.a == X86_LIR_BINARY_AND_BOOL ? 4u :
                        operands.a == X86_LIR_BINARY_BIT_OR_I32 ||
                        operands.a == X86_LIR_BINARY_OR_BOOL ? 1u : 6u;
                    if (destination >= 8u) emit_u8(cursor, 0x41u);
                    emit_u8(cursor, 0x83u);
                    emit_u8(cursor, 0xc0u | (extension << 3u) |
                        (destination & 7u));
                    emit_u8(cursor, immediate);
                }
                else if (direct)
                {
                    uint extension =
                        operands.a == X86_LIR_BINARY_ADD_I32 ? 0u :
                        operands.a == X86_LIR_BINARY_SUB_I32 ? 5u :
                        operands.a == X86_LIR_BINARY_BIT_AND_I32 ||
                        operands.a == X86_LIR_BINARY_AND_BOOL ? 4u :
                        operands.a == X86_LIR_BINARY_BIT_OR_I32 ||
                        operands.a == X86_LIR_BINARY_OR_BOOL ? 1u : 6u;
                    if (destination >= 8u) emit_u8(cursor, 0x41u);
                    emit_u8(cursor, 0x81u);
                    emit_u8(cursor, 0xc0u | (extension << 3u) |
                        (destination & 7u));
                    emit_u32(cursor, immediate);
                }
                else
                {
                    emit_u8(cursor,
                        operands.a == X86_LIR_BINARY_ADD_I32 ? 0x05u :
                        operands.a == X86_LIR_BINARY_SUB_I32 ? 0x2du :
                        operands.a == X86_LIR_BINARY_BIT_AND_I32 ||
                        operands.a == X86_LIR_BINARY_AND_BOOL ? 0x25u :
                        operands.a == X86_LIR_BINARY_BIT_OR_I32 ||
                        operands.a == X86_LIR_BINARY_OR_BOOL ? 0x0du : 0x35u);
                    emit_u32(cursor, immediate);
                }
            }
            if (!direct)
                store_value32(cursor, 0u, locations.result, function);
            return;
        }
        if (operands.a >= X86_LIR_BINARY_ADD_F32 &&
            operands.a <= X86_LIR_BINARY_DIV_F32)
        {
            emit_f32_binary(cursor, operands.a, locations.b, locations.c,
                locations.result);
            return;
        }
        if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
        {
            load_value64(cursor, locations.b, 0u, function);
            load_value32(cursor, locations.c, 1u, function);
            emit_u8(cursor, 0x48u);
            emit_u8(cursor, operands.a == X86_LIR_BINARY_SUB_I32 ? 0x29u : 0x01u);
            emit_u8(cursor, 0xc8u);
            store_value64(cursor, 0u, locations.result, function);
            return;
        }
        if (operands.a == X86_LIR_BINARY_ADD_I32 &&
            x86_lea_add32_preferred(locations.b, locations.c,
                locations.result))
        {
            emit_lea_add32(cursor, locations.b, locations.c,
                locations.result);
            return;
        }
        if (x86_location_is_register(locations.result) &&
            x86_direct_binary32_supported(operands.a) &&
            (locations.result != locations.c ||
             locations.result == locations.b ||
             x86_binary32_commutative(operands.a)))
        {
            uint right = locations.c;
            if (locations.result == locations.c &&
                locations.result != locations.b)
                right = locations.b;
            else move_location32(cursor, locations.b, locations.result);
            emit_binary32_to_register(cursor, operands.a, right,
                locations.result);
            return;
        }
        load_value32(cursor, locations.b, 0u, function);
        load_value32(cursor, locations.c, 1u, function);
        if (operands.a == X86_LIR_BINARY_ADD_I32) { emit_u8(cursor, 0x01u); emit_u8(cursor, 0xc8u); }
        else if (operands.a == X86_LIR_BINARY_SUB_I32) { emit_u8(cursor, 0x29u); emit_u8(cursor, 0xc8u); }
        else if (operands.a == X86_LIR_BINARY_MUL_I32)
        { emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xafu); emit_u8(cursor, 0xc1u); }
        else if (operands.a == X86_LIR_BINARY_DIV_I32 || operands.a == X86_LIR_BINARY_REM_I32)
        {
            bool is_unsigned = (operands.metadata & 0xffu) == 4u ||
                (operands.metadata & 0xffu) == 6u;
            if (is_unsigned)
            {
                // xor edx, edx; div ecx
                emit_u8(cursor, 0x31u); emit_u8(cursor, 0xd2u);
                emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xf1u);
            }
            else
            {
                // cdq; idiv ecx
                emit_u8(cursor, 0x99u); emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xf9u);
            }
            if (operands.a == X86_LIR_BINARY_REM_I32)
            { emit_u8(cursor, 0x89u); emit_u8(cursor, 0xd0u); }
        }
        else if (operands.a == X86_LIR_BINARY_BIT_AND_I32 || operands.a == X86_LIR_BINARY_AND_BOOL)
        { emit_u8(cursor, 0x21u); emit_u8(cursor, 0xc8u); }
        else if (operands.a == X86_LIR_BINARY_BIT_OR_I32 || operands.a == X86_LIR_BINARY_OR_BOOL)
        { emit_u8(cursor, 0x09u); emit_u8(cursor, 0xc8u); }
        else if (operands.a == X86_LIR_BINARY_BIT_XOR_I32)
        { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc8u); }
        else if (operands.a == X86_LIR_BINARY_SHL_I32)
        { emit_u8(cursor, 0xd3u); emit_u8(cursor, 0xe0u); }
        else if (operands.a == X86_LIR_BINARY_SHR_I32)
        {
            emit_u8(cursor, 0xd3u);
            emit_u8(cursor, (operands.metadata & 0xffu) == 4u ||
                (operands.metadata & 0xffu) == 6u ? 0xe8u : 0xf8u);
        }
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_COMPARE)
    {
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        {
            emit_compare32_immediate(cursor, operands.c, locations.b);
            emit_boolean_result(cursor,
                integer_setcc_opcode(operands.a, operands.metadata & 0xffu),
                locations.result, function);
            return;
        }
        if ((operands.metadata & 0xffu) == 5u)
        {
            emit_f32_compare(cursor, locations.b, locations.c);
            emit_boolean_result(cursor, float_setcc_opcode(operands.a),
                locations.result, function);
            return;
        }
        bool pointer = (operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER;
        if (pointer)
        {
            load_value64(cursor, locations.b, 0u, function);
            if ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) != 0u)
                load_value32(cursor, locations.c, 1u, function);
            else
                load_value64(cursor, locations.c, 1u, function);
            emit_u8(cursor, 0x48u);
        }
        else
        {
            emit_compare_locations32(cursor, locations.b, locations.c,
                function);
        }
        if (pointer) { emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u); }
        emit_boolean_result(cursor,
            integer_setcc_opcode(operands.a, operands.metadata & 0xffu),
            locations.result, function);
    }
    else if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        bool f32 = (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT;
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            emit_compare32_immediate(cursor, operands.b, locations.a);
        else if (f32)
            emit_f32_compare(cursor, locations.a, locations.b);
        else
        {
            bool pointer = (operands.metadata & 0xffu) ==
                SEMANTIC_LIR_TY_POINTER;
            if (pointer)
            {
                load_value64(cursor, locations.a, 0u, function);
                if ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) != 0u)
                    load_value32(cursor, locations.b, 1u, function);
                else
                    load_value64(cursor, locations.b, 1u, function);
                emit_u8(cursor, 0x48u);
            }
            else
            {
                emit_compare_locations32(cursor, locations.a, locations.b,
                    function);
            }
            if (pointer) { emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u); }
        }
        uint target = layout.body_offset +
            target_byte_offset[core.result_or_target];
        uint next = cursor + 6u;
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, f32
            ? float_false_jcc_opcode(core.local_ordinal)
            : integer_false_jcc_opcode(
                core.local_ordinal, operands.metadata & 0xffu));
        emit_u32(cursor, target - next);
    }
    else if (core.op == X86_LIR_OP_SELECT_STORE)
    {
        uint destination = declaration_location(core.result_or_target);
        bool register_destination = x86_location_is_register(destination);
        uint selected_register = register_destination
            ? x86_location_payload(destination) : 2u;
        if (register_destination)
            move_location32(cursor, locations.result, destination);
        else load_value32(cursor, locations.result, 2u, function);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            emit_compare32_immediate(cursor, operands.b, locations.a);
        else
        {
            emit_compare_locations32(cursor, locations.a, locations.b,
                function);
        }
        // Loading the true candidate after CMP is safe because MOV preserves
        // flags; CMOV then updates the final declaration register in place.
        load_value32(cursor, locations.c, 0u, function);
        if (selected_register >= 8u) emit_u8(cursor, 0x44u);
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, integer_cmovcc_opcode(
            core.local_ordinal, operands.metadata & 0xffu));
        emit_u8(cursor, 0xc0u | ((selected_register & 7u) << 3u));
        if (!register_destination)
            store_value32(cursor, 2u, destination, function);
    }
    else if (core.op == X86_LIR_OP_UNARY)
    {
        if (operands.a == X86_LIR_UNARY_NEG_F32)
        {
            move_f32_to_gpr(cursor, locations.b, 0u);
            emit_u8(cursor, 0x35u); emit_u32(cursor, 0x80000000u);
            move_f32_from_gpr(cursor, 0u, locations.result);
            return;
        }
        bool direct = x86_location_is_register(locations.result) &&
            (operands.a == X86_LIR_UNARY_NEG_I32 ||
             operands.a == X86_LIR_UNARY_NOT_BOOL);
        if (direct)
            move_location32(cursor, locations.b, locations.result);
        else
            load_value32(cursor, locations.b, 0u, function);
        uint destination = direct
            ? x86_location_payload(locations.result) : 0u;
        if (operands.a == X86_LIR_UNARY_NEG_I32)
        {
            if (direct && destination >= 8u) emit_u8(cursor, 0x41u);
            emit_u8(cursor, 0xf7u);
            emit_u8(cursor, 0xd8u | (destination & 7u));
        }
        else
        {
            if (direct && destination >= 8u) emit_u8(cursor, 0x45u);
            emit_u8(cursor, 0x85u);
            emit_u8(cursor, 0xc0u | ((destination & 7u) << 3u) |
                (destination & 7u));
            emit_boolean_result(cursor, 0x94u, locations.result, function);
        }
        if (!direct && operands.a != X86_LIR_UNARY_NOT_BOOL)
            store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_RETURN || core.op == X86_LIR_OP_RETURN_VOID)
    {
        if (operands.c != 0u)
        {
            if (operands.c > 2u)
            {
                load_stack64(cursor,
                    hidden_sret_slot(function, semantic_function), 0u);
            }
        }
        else if (operands.a == INVALID || core.op == X86_LIR_OP_RETURN_VOID)
        { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u); }
        else if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_to_gpr(cursor, locations.a, 0u);
        else if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
            load_value64(cursor, locations.a, 0u, function);
        else load_value32(cursor, locations.a, 0u, function);
        restore_registers(cursor, saved_mask,
            base_frame_slots(function, semantic_function));
        if (stackless_caller(function, semantic_function))
            emit_u8(cursor, 0x59u);
        else if (!frameless_function(function, semantic_function))
            emit_u8(cursor, 0xc9u);
        emit_u8(cursor, 0xc3u);
    }
    else if (core.op == X86_LIR_OP_INLINE_RESULT)
    {
        if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_location(cursor, locations.a, locations.result);
        else if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
            move_location64(cursor, locations.a, locations.result);
        else
            move_location32(cursor, locations.a, locations.result);
    }
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        uint destination = X86_LOCATION_REGISTER |
            x86_abi_argument_register(operands.b);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            emit_imm32_to_location(cursor, operands.a, destination);
        else
        {
            bool wide = (operands.metadata &
                (X86_LIR_METADATA_AGGREGATE |
                 X86_LIR_METADATA_WIDE)) != 0u;
            if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
                move_f32_to_gpr(cursor, locations.a,
                    x86_location_payload(destination));
            else if (wide) move_location64(cursor, locations.a, destination);
            else move_location32(cursor, locations.a, destination);
        }
    }
    else if (core.op == X86_LIR_OP_CALL)
    {
        uint callee_index = target_function_index_by_semantic[operands.a];
        if (callee_index >= target_function_count[0u]) return;
        TargetLirFunction callee = target_functions[callee_index];
        uint target = layout.body_offset + target_byte_offset[callee.instruction_start];
        uint storage_slot = value_slot(locations.result, function) + 1u;
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u && operands.c > 2u)
            emit_stack_address(cursor, 7u, storage_slot);
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            if (operands.c <= 2u)
            {
                store_stack64(cursor, 0u, storage_slot);
                if (operands.c > 1u) store_stack64(cursor, 2u, storage_slot + 1u);
                emit_stack_address(cursor, 0u, storage_slot);
                store_value64(cursor, 0u, locations.result, function);
            }
            else store_value64(cursor, 0u, locations.result, function);
        }
        else if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_from_gpr(cursor, 0u, locations.result);
        else if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
            store_value64(cursor, 0u, locations.result, function);
        else store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_CALL_SYMBOL)
    {
        // Object projection records a PC-relative relocation at the four-byte
        // placeholder following E8. Executable mode never admits unresolved
        // dependencies, so no symbol policy is hidden in this emitter.
        uint storage_slot = value_slot(locations.result, function) + 1u;
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u &&
            core.local_ordinal > 2u)
            emit_stack_address(cursor, 7u, storage_slot);
        emit_u8(cursor, 0xe8u);
        emit_u32(cursor, 0u);
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            if (core.local_ordinal <= 2u)
            {
                store_stack64(cursor, 0u, storage_slot);
                if (core.local_ordinal > 1u)
                    store_stack64(cursor, 2u, storage_slot + 1u);
                emit_stack_address(cursor, 0u, storage_slot);
                store_value64(cursor, 0u, locations.result, function);
            }
            else store_value64(cursor, 0u, locations.result, function);
        }
        else if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            move_f32_from_gpr(cursor, 0u, locations.result);
        else if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
            store_value64(cursor, 0u, locations.result, function);
        else store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_CALL_HOST && operands.a == HOST_SERVICE_I32_TO_F32)
    {
        // The preceding CALL_ARG row placed the signed i32 in EDI. Convert it
        // directly and retain the f32 result in the ordinary value-slot domain.
        emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu);
        emit_u8(cursor, 0x2au); emit_u8(cursor, 0xc7u);
        cursor = move_f32_from_xmm(cursor, 0u, locations.result);
    }
    else if (core.op == X86_LIR_OP_CALL_HOST && x86_runtime_service_supported(operands.a))
    {
        uint target = layout.runtime_offset + x86_runtime_service_offset(operands.a);
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
        if (x86_runtime_service_has_result(operands.a))
        {
            if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
                store_value64(cursor, 0u, locations.result, function);
            else store_value32(cursor, 0u, locations.result, function);
        }
    }
    else if (core.op == X86_LIR_OP_PRINT_I32 && operands.a == 1u)
    {
        uint target = layout.runtime_offset + X86_RUNTIME_PRINT_I32_OFFSET;
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
    }
    else if (core.op == X86_LIR_OP_INTRINSIC_IDENTITY)
    {
        // The preceding CALL_ARG row placed the aggregate pointer in RDI.
        store_value64(cursor, 7u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
    {
        if (operands.c <= 2u)
        {
            if (operands.b == 0u)
            {
                load_value64(cursor, locations.a, 0u, function);
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x00u);
            }
            else
            {
                load_value64(cursor, locations.a, 1u, function);
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x91u);
                emit_u32(cursor, 0u - operands.b * 8u);
            }
        }
        else
        {
            load_value64(cursor, locations.a, 0u, function);
            load_stack64(cursor,
                hidden_sret_slot(function, semantic_function), 10u);
            if (operands.b == 0u)
            {
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x08u);
                emit_u8(cursor, 0x49u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x0au);
            }
            else
            {
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x88u);
                emit_u32(cursor, 0u - operands.b * 8u);
                emit_u8(cursor, 0x49u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x8au);
                emit_u32(cursor, 0u - operands.b * 8u);
            }
        }
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_COPY_WORD)
    {
        load_value64(cursor, locations.a, 0u, function);
        if (operands.b == 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x08u);
        }
        else
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x88u);
            emit_u32(cursor, 0u - operands.b * 8u);
        }
        store_value64(cursor, 1u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_STRING_ADDR)
    {
        uint count = min(gParams.token_capacity, semantic_lir_string_total[0u]);
        if (operands.a >= count) return;
        SemanticLirString string = semantic_lir_strings[operands.a];
        uint address = ELF_BASE_VADDR + layout.rodata_offset + string.data_offset;
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xb8u);
        emit_u64(cursor, address, 0u);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_STRING_LEN)
    {
        uint count = min(gParams.token_capacity, semantic_lir_string_total[0u]);
        if (operands.a >= count) return;
        emit_u8(cursor, 0xb8u); emit_u32(cursor, semantic_lir_strings[operands.a].decoded_len);
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_BRANCH)
    {
        uint target = layout.body_offset + target_byte_offset[operands.b];
        if (operands.a == INVALID)
        {
            uint next = cursor + 5u;
            emit_u8(cursor, 0xe9u); emit_u32(cursor, target - next);
        }
        else
        {
            emit_test_location32(cursor, locations.a, function);
            uint next = cursor + 6u;
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x84u); emit_u32(cursor, target - next);
        }
    }
}

uint le32_byte(uint value, uint byte_i) { return (value >> (byte_i * 8u)) & 0xffu; }

uint header_byte(uint pos, X86ArtifactLayout layout)
{
    if (pos == 0u) return 0x7fu;
    if (pos == 1u) return 0x45u;
    if (pos == 2u) return 0x4cu;
    if (pos == 3u) return 0x46u;
    if (pos == 4u) return 2u;
    if (pos == 5u || pos == 6u) return 1u;
    if (pos == 16u) return 2u;
    if (pos == 18u) return 0x3eu;
    if (pos == 20u) return 1u;
    if (pos >= 24u && pos < 28u) return le32_byte(ELF_BASE_VADDR + layout.text_offset, pos - 24u);
    if (pos == 32u || pos == 52u) return 64u;
    if (pos == 54u) return 56u;
    if (pos == 56u) return 1u;
    if (pos == 64u) return 1u;
    if (pos == 68u) return 5u;
    if (pos >= 80u && pos < 84u) return le32_byte(ELF_BASE_VADDR, pos - 80u);
    if (pos >= 88u && pos < 92u) return le32_byte(ELF_BASE_VADDR, pos - 88u);
    if (pos >= 96u && pos < 100u) return le32_byte(layout.file_length, pos - 96u);
    if (pos >= 104u && pos < 108u) return le32_byte(layout.file_length, pos - 104u);
    if (pos == 113u) return 0x10u;
    return 0u;
}

void emit_header_and_wrapper(X86ArtifactLayout layout)
{
    for (uint pos = 0u; pos < layout.text_offset; pos += 1u)
        store_byte(pos, header_byte(pos, layout));
    uint cursor = layout.text_offset;
    // Preserve the kernel-provided process stack for argc/argv runtime thunks.
    emit_u8(cursor, 0x49u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0xe7u);
    uint main_pos = layout.body_offset + layout.entrypoint_body_offset;
    emit_u8(cursor, 0xe8u); emit_u32(cursor, main_pos - cursor - 4u);
    emit_u8(cursor, 0x89u); emit_u8(cursor, 0xc7u);
    emit_u8(cursor, 0xb8u); emit_u32(cursor, 60u);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x05u);
}

void emit_rodata_word(uint word_row, X86ArtifactLayout layout)
{
    uint byte_count = min(layout.rodata_length, semantic_lir_string_pool_len[0u]);
    uint byte_start = word_row * 4u;
    if (byte_start >= byte_count) return;
    uint packed = semantic_lir_string_data[word_row];
    for (uint byte_i = 0u; byte_i < 4u && byte_start + byte_i < byte_count; byte_i += 1u)
        store_byte(layout.rodata_offset + byte_start + byte_i, packed >> (byte_i * 8u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    if (layout.status != 0u) return;
    emit_rodata_word(row, layout);
    if (row >= total) return;
    if (row == 0u) emit_header_and_wrapper(layout);
    X86LirCore core = target_lir_core[page_row];
    uint function_id = semantic_function_id_by_hir[core.source_hir];
    uint semantic_function_count = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    if (function_id >= semantic_function_count) return;
    uint function_index = target_function_index_by_semantic[function_id];
    if (function_index >= target_function_count[0u]) return;
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    uint saved_mask = x86_saved_gpr_mask_by_function[function_id];
    uint cursor = layout.body_offset + target_byte_offset[row];
    if (row == function.instruction_start)
        emit_prologue(cursor, function, semantic_function, saved_mask);
    cursor += x86_safety_guard_bytes(core, target_lir_operands[page_row],
        target_lir_locations[page_row]);
    emit_instruction(cursor, core, target_lir_operands[page_row],
                     target_lir_locations[page_row], function,
                     semantic_function, layout, saved_mask);
    bool final_explicit_return = core.op == X86_LIR_OP_RETURN ||
        core.op == X86_LIR_OP_RETURN_VOID;
    if (row + 1u == function.instruction_start + function.instruction_count &&
        !final_explicit_return)
        emit_footer(cursor, function, semantic_function, saved_mask);
}
