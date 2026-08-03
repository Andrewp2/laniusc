import codegen.lowering_ir;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.location_common;
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
    emit_u8(cursor, 0x85u | ((destination & 7u) << 3u));
    emit_u32(cursor, displacement(slot));
}

void store_stack32(inout uint cursor, uint source, uint slot)
{
    if (source >= 8u) emit_u8(cursor, 0x44u);
    emit_u8(cursor, 0x89u);
    emit_u8(cursor, 0x85u | ((source & 7u) << 3u));
    emit_u32(cursor, displacement(slot));
}

void load_stack64(inout uint cursor, uint slot, uint destination)
{
    emit_u8(cursor, 0x48u | (destination >= 8u ? 4u : 0u));
    emit_u8(cursor, 0x8bu);
    emit_u8(cursor, 0x85u | ((destination & 7u) << 3u));
    emit_u32(cursor, displacement(slot));
}

void store_stack64(inout uint cursor, uint source, uint slot)
{
    emit_u8(cursor, 0x48u | (source >= 8u ? 4u : 0u));
    emit_u8(cursor, 0x89u);
    emit_u8(cursor, 0x85u | ((source & 7u) << 3u));
    emit_u32(cursor, displacement(slot));
}

void load_eax(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x85u); emit_u32(cursor, displacement(slot));
}
void load_ecx(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x8du); emit_u32(cursor, displacement(slot));
}
void store_eax(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x89u); emit_u8(cursor, 0x85u); emit_u32(cursor, displacement(slot));
}
void load_rax(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x85u);
    emit_u32(cursor, displacement(slot));
}
void load_rcx(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x8du);
    emit_u32(cursor, displacement(slot));
}
void store_rax(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x85u);
    emit_u32(cursor, displacement(slot));
}
void store_edx(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x89u); emit_u8(cursor, 0x95u); emit_u32(cursor, displacement(slot));
}
void store_rdx(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x95u);
    emit_u32(cursor, displacement(slot));
}
void load_r10(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x4cu); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x95u);
    emit_u32(cursor, displacement(slot));
}
void load_xmm0(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x10u);
    emit_u8(cursor, 0x85u); emit_u32(cursor, displacement(slot));
}
void load_xmm1(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x10u);
    emit_u8(cursor, 0x8du); emit_u32(cursor, displacement(slot));
}
void store_xmm0(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x11u);
    emit_u8(cursor, 0x85u); emit_u32(cursor, displacement(slot));
}
uint argument_register(uint ordinal)
{
    static const uint registers[6] = {7u, 6u, 2u, 1u, 8u, 9u};
    return registers[min(ordinal, 5u)];
}

void move_eax_to_argument(inout uint cursor, uint ordinal)
{
    if (ordinal < 4u)
    {
        static const uint modrm[4] = {0xc7u, 0xc6u, 0xc2u, 0xc1u};
        emit_u8(cursor, 0x89u); emit_u8(cursor, modrm[ordinal]);
    }
    else
    {
        emit_u8(cursor, 0x41u); emit_u8(cursor, 0x89u);
        emit_u8(cursor, ordinal == 4u ? 0xc0u : 0xc1u);
    }
}

void move_rax_to_argument(inout uint cursor, uint ordinal)
{
    if (ordinal < 4u)
    {
        static const uint modrm[4] = {0xc7u, 0xc6u, 0xc2u, 0xc1u};
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, modrm[ordinal]);
    }
    else
    {
        emit_u8(cursor, 0x49u); emit_u8(cursor, 0x89u);
        emit_u8(cursor, ordinal == 4u ? 0xc0u : 0xc1u);
    }
}

uint base_frame_slots(TargetLirFunction function, SemanticLirFunction semantic_function)
{
    return function.instruction_count + semantic_function.param_count +
        semantic_function.local_count;
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
    return value_row >= function.instruction_start &&
           value_row < function.instruction_start + function.instruction_count
        ? value_row - function.instruction_start : 0u;
}

void load_value32(inout uint cursor, uint location, uint destination,
                  TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move32_register(cursor, x86_location_payload(location), destination);
    else load_stack32(cursor, value_slot(x86_location_payload(location), function), destination);
}

void store_value32(inout uint cursor, uint source, uint location,
                   TargetLirFunction function)
{
    if (x86_location_is_register(location))
        move32_register(cursor, source, x86_location_payload(location));
    else store_stack32(cursor, source, value_slot(x86_location_payload(location), function));
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

void load_declaration32(inout uint cursor, uint location, uint destination)
{
    if (x86_location_is_register(location))
        move32_register(cursor, x86_location_payload(location), destination);
    else load_stack32(cursor, x86_location_payload(location), destination);
}

void store_declaration32(inout uint cursor, uint source, uint location)
{
    if (x86_location_is_register(location))
        move32_register(cursor, source, x86_location_payload(location));
    else store_stack32(cursor, source, x86_location_payload(location));
}

void load_declaration64(inout uint cursor, uint location, uint destination)
{
    if (x86_location_is_register(location))
        move64_register(cursor, x86_location_payload(location), destination);
    else load_stack64(cursor, x86_location_payload(location), destination);
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
    emit_u8(cursor, 0x55u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0xe5u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x81u); emit_u8(cursor, 0xecu);
    emit_u32(cursor, frame_size(function, semantic_function, saved_mask));
    uint first_saved_slot = base_frame_slots(function, semantic_function);
    save_registers(cursor, saved_mask, first_saved_slot);
    for (uint ordinal = 0u;
         ordinal < min(semantic_function.param_count, 6u); ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[semantic_function.param_start + ordinal];
        store_declaration64(cursor, argument_register(ordinal),
            declaration_location(param.declaration_id));
    }
}

void emit_footer(inout uint cursor, TargetLirFunction function,
                 SemanticLirFunction semantic_function, uint saved_mask)
{
    emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u);
    restore_registers(cursor, saved_mask, base_frame_slots(function, semantic_function));
    emit_u8(cursor, 0xc9u); emit_u8(cursor, 0xc3u);
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
    bool is_unsigned = type_id == 4u || type_id == 6u;
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

void emit_instruction(inout uint cursor, X86LirCore core, X86LirOperands operands,
                      X86LirLocations locations,
                      TargetLirFunction function, SemanticLirFunction semantic_function,
                      X86ArtifactLayout layout, uint saved_mask)
{
    uint result_slot = value_slot(core.result_or_target, function);
    if (core.op == X86_LIR_OP_IMM_I32)
    {
        emit_u8(cursor, 0xb8u); emit_u32(cursor, operands.a);
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_ALIAS)
    {
        // Value slots are eight bytes so aggregate references are first-class
        // values. Scalar consumers still read the low dword.
        uint source = declaration_location(operands.a);
        load_declaration64(cursor, source, 0u);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        bool aggregate_reference =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        if (aggregate_reference)
        {
            // Aggregate variables have value semantics. The source points at
            // a runtime-owned object whose count header is at [ptr - 8]; the
            // shared clone helper copies the complete object before storing
            // the new declaration pointer.
            load_value64(cursor, locations.b, 0u, function);
            move_rax_to_argument(cursor, 0u);
            uint clone_target = layout.runtime_offset +
                X86_RUNTIME_AGGREGATE_CLONE_OFFSET;
            uint clone_next = cursor + 5u;
            emit_u8(cursor, 0xe8u);
            emit_u32(cursor, clone_target - clone_next);
            store_declaration64(cursor, 0u, declaration_location(operands.a));
        }
        else
        {
            load_value32(cursor, locations.b, 0u, function);
            store_declaration32(cursor, 0u, declaration_location(operands.a));
        }
    }
    else if (core.op == X86_LIR_OP_ARRAY_ADDR)
    {
        // Allocate aggregate storage outside the current function frame.
        // Nested aggregate fields therefore remain valid after a callee
        // returns instead of dangling into its stack frame.
        emit_u8(cursor, 0xbfu); // mov edi, imm32
        emit_u32(cursor, (operands.b + 1u) * 8u);
        uint target = layout.runtime_offset + X86_RUNTIME_ALLOC_OFFSET;
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u);
        emit_u32(cursor, target - next);
        // The count header is outside the public object pointer. It lets
        // aggregate assignment clone values without recovering source type
        // metadata in the native emitter.
        emit_u8(cursor, 0xc7u); emit_u8(cursor, 0x00u);
        emit_u32(cursor, operands.b);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x83u);
        emit_u8(cursor, 0xc0u); emit_u8(cursor, 0x08u);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_ARRAY_INIT)
    {
        // Store one field/element into the owning aggregate allocation.
        load_value64(cursor, locations.c, 0u, function);
        load_value64(cursor, locations.a, 1u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
        emit_u32(cursor, operands.b * 8u);
    }
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value32(cursor, locations.b, 1u, function);
        // Aggregate storage uses ascending eight-byte slots.  The old stack
        // representation addressed fields below the base and negated the
        // index here; heap-backed aggregates must use the ordinary positive
        // scaled index instead.
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
        emit_u8(cursor, 0x04u); emit_u8(cursor, 0xc8u);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
    {
        load_value64(cursor, locations.a, 0u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x80u);
        emit_u32(cursor, operands.b * operands.c);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value32(cursor, locations.b, 1u, function);
        load_value32(cursor, locations.c, 2u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u);
        emit_u8(cursor, 0x14u); emit_u8(cursor, 0xc8u);
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value32(cursor, locations.c, 1u, function);
        uint stride = operands.metadata >> 24u;
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
        emit_u32(cursor, operands.b * stride);
    }
    else if (core.op == X86_LIR_OP_BINARY)
    {
        if (operands.a >= X86_LIR_BINARY_ADD_F32)
        {
            load_xmm0(cursor, value_slot(operands.b, function));
            load_xmm1(cursor, value_slot(operands.c, function));
            emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu);
            emit_u8(cursor,
                operands.a == X86_LIR_BINARY_ADD_F32 ? 0x58u :
                operands.a == X86_LIR_BINARY_SUB_F32 ? 0x5cu :
                operands.a == X86_LIR_BINARY_MUL_F32 ? 0x59u : 0x5eu);
            emit_u8(cursor, 0xc1u);
            store_xmm0(cursor, result_slot);
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
            emit_u8(cursor, 0x99u); emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xf9u);
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
        { emit_u8(cursor, 0xd3u); emit_u8(cursor, 0xf8u); }
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_COMPARE)
    {
        if ((operands.metadata & 0xffu) == 5u)
        {
            load_xmm0(cursor, value_slot(operands.b, function));
            load_xmm1(cursor, value_slot(operands.c, function));
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x2eu); emit_u8(cursor, 0xc1u);
            emit_u8(cursor, 0x0fu); emit_u8(cursor, float_setcc_opcode(operands.a)); emit_u8(cursor, 0xc0u);
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u); emit_u8(cursor, 0xc0u);
            store_eax(cursor, result_slot);
            return;
        }
        load_value32(cursor, locations.b, 0u, function);
        load_value32(cursor, locations.c, 1u, function);
        emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u);
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, integer_setcc_opcode(operands.a, operands.metadata & 0xffu));
        emit_u8(cursor, 0xc0u);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u); emit_u8(cursor, 0xc0u);
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_UNARY)
    {
        load_value32(cursor, locations.b, 0u, function);
        if (operands.a == X86_LIR_UNARY_NEG_I32)
        { emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xd8u); }
        else if (operands.a == X86_LIR_UNARY_NEG_F32)
        { emit_u8(cursor, 0x35u); emit_u32(cursor, 0x80000000u); }
        else
        {
            emit_u8(cursor, 0x83u); emit_u8(cursor, 0xf8u); emit_u8(cursor, 0u);
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x94u); emit_u8(cursor, 0xc0u);
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u); emit_u8(cursor, 0xc0u);
        }
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_RETURN || core.op == X86_LIR_OP_RETURN_VOID)
    {
        if (operands.c != 0u)
        {
            load_value64(cursor, locations.a, 0u, function);
        }
        else if (operands.a == INVALID || core.op == X86_LIR_OP_RETURN_VOID)
        { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u); }
        else load_value32(cursor, locations.a, 0u, function);
        restore_registers(cursor, saved_mask,
            base_frame_slots(function, semantic_function));
        emit_u8(cursor, 0xc9u); emit_u8(cursor, 0xc3u);
    }
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        bool wide = (operands.metadata &
            (X86_LIR_METADATA_AGGREGATE | X86_LIR_METADATA_WIDE)) != 0u;
        if (wide)
        {
            load_value64(cursor, locations.a, 0u, function);
            move_rax_to_argument(cursor, operands.b);
        }
        else
        {
            load_value32(cursor, locations.a, 0u, function);
            move_eax_to_argument(cursor, operands.b);
        }
    }
    else if (core.op == X86_LIR_OP_CALL)
    {
        uint callee_index = target_function_index_by_semantic[operands.a];
        if (callee_index >= target_function_count[0u]) return;
        TargetLirFunction callee = target_functions[callee_index];
        uint target = layout.body_offset + target_byte_offset[callee.instruction_start];
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            store_value64(cursor, 0u, locations.result, function);
        }
        else store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_CALL_SYMBOL)
    {
        // Object projection records a PC-relative relocation at the four-byte
        // placeholder following E8. Executable mode never admits unresolved
        // dependencies, so no symbol policy is hidden in this emitter.
        emit_u8(cursor, 0xe8u);
        emit_u32(cursor, 0u);
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
            store_value64(cursor, 0u, locations.result, function);
        else
            store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_CALL_HOST && operands.a == HOST_SERVICE_I32_TO_F32)
    {
        // The preceding CALL_ARG row placed the signed i32 in EDI. Convert it
        // directly and retain the f32 result in the ordinary value-slot domain.
        emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu);
        emit_u8(cursor, 0x2au); emit_u8(cursor, 0xc7u);
        store_xmm0(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
    {
        // Aggregate returns are pointer-valued. The actual RETURN row loads
        // the object pointer into RAX; these legacy expansion rows are kept
        // in the target stream for stable scheduling but emit no bytes.
    }
    else if (core.op == X86_LIR_OP_CALL_HOST && x86_runtime_service_supported(operands.a))
    {
        uint target = layout.runtime_offset + x86_runtime_service_offset(operands.a);
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
        if (x86_runtime_service_has_result(operands.a))
            store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_PRINT_I32 && operands.a == 1u)
    {
        uint target = layout.runtime_offset + X86_RUNTIME_PRINT_I32_OFFSET;
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
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
            load_value32(cursor, locations.a, 0u, function);
            emit_u8(cursor, 0x85u); emit_u8(cursor, 0xc0u);
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
    emit_instruction(cursor, core, target_lir_operands[page_row],
                     target_lir_locations[page_row], function,
                     semantic_function, layout, saved_mask);
    if (row + 1u == function.instruction_start + function.instruction_count)
        emit_footer(cursor, function, semantic_function, saved_mask);
}
