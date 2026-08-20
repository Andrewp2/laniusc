import codegen.lowering_ir;
import codegen.lir.x86.common;
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
StructuredBuffer<uint> x86_decl_location_by_token;
StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<uint> artifact_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

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

uint value_slot(uint value_row, TargetLirFunction function)
{
    return x86_location_payload(value_row);
}

void load_value32(inout uint cursor, uint location, uint destination,
                  TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move32_register(cursor, x86_location_payload(location), destination);
    else
    {
        if (destination >= 8u) emit_u8(cursor, 0x44u);
        emit_u8(cursor, 0x8bu);
        emit_stack_modrm(cursor, destination,
            value_slot(x86_location_payload(location), function));
    }
}

uint declaration_location(uint token)
{
    uint location = token < gParams.token_capacity
        ? x86_decl_location_by_token[token] : X86_LOCATION_INVALID;
    return location == X86_LOCATION_INVALID ? 0u : location;
}

uint hidden_sret_slot(TargetLirFunction function)
{
    return function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
}

uint base_frame_slots(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return hidden_sret_slot(function) +
        (semantic_function.result_word_count > 2u ? 1u : 0u);
}

uint param_store_bytes(TargetLirFunction target_function,
                       SemanticLirFunction function, uint hidden_sret)
{
    uint bytes = hidden_sret != 0u
        ? x86_stack64_operand_bytes(hidden_sret_slot(target_function)) : 0u;
    uint abi_ordinal = hidden_sret;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        uint width = x86_abi_type_width(param.type_id);
        if (abi_ordinal + width > 6u) break;
        uint destination = declaration_location(param.declaration_id);
        bytes += x86_move64_from_fixed_bytes(x86_abi_argument_register(abi_ordinal), destination);
        if (width == 2u)
            bytes += x86_move64_from_fixed_bytes(x86_abi_argument_register(abi_ordinal + 1u),
                destination + 1u);
        abi_ordinal += width;
    }
    return bytes;
}

uint prologue_bytes(TargetLirFunction target_function,
                    SemanticLirFunction function, uint saved_mask)
{
    uint hidden_sret = function.result_word_count > 2u ? 1u : 0u;
    return 11u + x86_saved_gpr_frame_bytes(saved_mask,
            base_frame_slots(target_function, function)) +
        param_store_bytes(target_function, function, hidden_sret);
}

void emit_exit(inout uint cursor, uint code)
{
    emit_u8(cursor, 0xbfu); emit_u32(cursor, code);
    emit_u8(cursor, 0xb8u); emit_u32(cursor, 60u);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x05u);
}

void emit_guards(inout uint cursor, X86LirCore core, X86LirOperands operands,
                 X86LirLocations locations, TargetLirFunction function)
{
    if ((core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE) &&
        core.local_ordinal != 0xffffffffu)
    {
        load_value32(cursor, locations.b, 1u, function);
        emit_u8(cursor, 0x81u); emit_u8(cursor, 0xf9u);
        emit_u32(cursor, core.local_ordinal);
        emit_u8(cursor, 0x72u); emit_u8(cursor, 12u);
        emit_exit(cursor, 101u);
        return;
    }
    if (x86_safety_shift(core, operands))
    {
        load_value32(cursor, locations.c, 1u, function);
        emit_u8(cursor, 0x83u); emit_u8(cursor, 0xf9u); emit_u8(cursor, 31u);
        emit_u8(cursor, 0x76u); emit_u8(cursor, 12u);
        emit_exit(cursor, 102u);
        return;
    }
    if (!x86_safety_integer_division(core, operands)) return;
    load_value32(cursor, locations.c, 1u, function);
    emit_u8(cursor, 0x85u); emit_u8(cursor, 0xc9u);
    emit_u8(cursor, 0x75u); emit_u8(cursor, 12u);
    emit_exit(cursor, 103u);
    if ((operands.metadata & 0xffu) != 3u) return;
    uint lhs_load_bytes = x86_move32_to_fixed_bytes(locations.b, 0u);
    emit_u8(cursor, 0x83u); emit_u8(cursor, 0xf9u); emit_u8(cursor, 0xffu);
    emit_u8(cursor, 0x75u); emit_u8(cursor, lhs_load_bytes + 19u);
    load_value32(cursor, locations.b, 0u, function);
    emit_u8(cursor, 0x3du); emit_u32(cursor, 0x80000000u);
    emit_u8(cursor, 0x75u); emit_u8(cursor, 12u);
    emit_exit(cursor, 104u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= total) return;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    if (layout.status != 0u) return;
    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    X86LirLocations locations = target_lir_locations[page_row];
    if (x86_safety_guard_bytes(core, operands, locations) == 0u) return;
    uint function_id = semantic_function_id_by_hir[core.source_hir];
    uint semantic_count = min(gParams.function_capacity, semantic_lir_function_total[0u]);
    if (function_id >= semantic_count) return;
    uint function_index = target_function_index_by_semantic[function_id];
    if (function_index >= target_function_count[0u]) return;
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    uint saved_mask = x86_saved_gpr_mask_by_function[function_id];
    uint cursor = layout.body_offset + target_byte_offset[row];
    if (row == function.instruction_start)
        cursor += prologue_bytes(function, semantic_function, saved_mask);
    emit_guards(cursor, core, operands, locations, function);
}
