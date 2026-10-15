import primitive_types;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.storage_layout;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.location_common;
import codegen.lir.x86.frame_layout;
import codegen.lir.x86.parameter_values;
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
StructuredBuffer<uint4> x86_place_storage_by_token;
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

uint displacement(uint slot) { return x86_native_word_displacement(slot + 1u); }

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

uint hidden_sret_slot(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
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

void load_value64(inout uint cursor, uint location, uint destination,
                  TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move64_register(cursor, x86_location_payload(location), destination);
    else load_stack64(cursor, value_slot(x86_location_payload(location), function), destination);
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
    return bytes + x86_parameter_copy_bytes(target_function, function,
        semantic_lir_params, x86_decl_location_by_token);
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
