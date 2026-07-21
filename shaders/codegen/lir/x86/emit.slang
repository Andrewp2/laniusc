import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<uint> scheduled_function_id;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> x86_frame_slot_by_decl_token;
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

uint displacement(uint slot) { return 0u - 8u * (slot + 1u); }

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
void store_rax(inout uint cursor, uint slot)
{
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x85u);
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
void store_param(inout uint cursor, uint slot, uint ordinal)
{
    if (ordinal < 4u)
    {
        static const uint modrm[4] = {0xbdu, 0xb5u, 0x95u, 0x8du};
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, modrm[ordinal]);
    }
    else
    {
        emit_u8(cursor, 0x4cu); emit_u8(cursor, 0x89u);
        emit_u8(cursor, ordinal == 4u ? 0x85u : 0x8du);
    }
    emit_u32(cursor, displacement(slot));
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

uint frame_size(TargetLirFunction function, SemanticLirFunction semantic_function)
{
    uint slots = function.instruction_count + semantic_function.param_count +
        semantic_function.local_count;
    return ((slots * 8u + 15u) / 16u) * 16u;
}

void emit_prologue(inout uint cursor, TargetLirFunction function,
                   SemanticLirFunction semantic_function)
{
    emit_u8(cursor, 0x55u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0xe5u);
    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x81u); emit_u8(cursor, 0xecu);
    emit_u32(cursor, frame_size(function, semantic_function));
    for (uint ordinal = 0u; ordinal < min(semantic_function.param_count, 6u); ordinal += 1u)
        store_param(cursor, function.instruction_count + ordinal, ordinal);
}

void emit_footer(inout uint cursor)
{
    emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u);
    emit_u8(cursor, 0xc9u); emit_u8(cursor, 0xc3u);
}

uint value_slot(uint value_row, TargetLirFunction function)
{
    return value_row >= function.instruction_start &&
           value_row < function.instruction_start + function.instruction_count
        ? value_row - function.instruction_start : 0u;
}

uint declaration_slot(uint declaration_token)
{
    return declaration_token < gParams.token_capacity
        ? x86_frame_slot_by_decl_token[declaration_token] : 0u;
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
                      TargetLirFunction function, X86ArtifactLayout layout)
{
    uint result_slot = value_slot(core.result_or_target, function);
    if (core.op == X86_LIR_OP_IMM_I32)
    {
        emit_u8(cursor, 0xb8u); emit_u32(cursor, operands.a); store_eax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_ALIAS)
    {
        // Value slots are eight bytes so aggregate references are first-class
        // values. Scalar consumers still read the low dword.
        load_rax(cursor, declaration_slot(operands.a)); store_rax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        bool aggregate_reference =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        if (aggregate_reference)
        {
            load_rax(cursor, value_slot(operands.b, function));
            store_rax(cursor, declaration_slot(operands.a));
        }
        else
        {
            load_eax(cursor, value_slot(operands.b, function));
            store_eax(cursor, declaration_slot(operands.a));
        }
    }
    else if (core.op == X86_LIR_OP_ARRAY_ADDR)
    {
        uint first_element_slot = value_slot(operands.a, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du); emit_u8(cursor, 0x85u);
        emit_u32(cursor, displacement(first_element_slot));
        store_rax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_ARRAY_INIT)
    {
        load_eax(cursor, value_slot(operands.a, function));
        store_eax(cursor, value_slot(operands.c, function));
    }
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        load_rax(cursor, value_slot(operands.a, function));
        load_ecx(cursor, value_slot(operands.b, function));
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xd9u);
        emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x04u); emit_u8(cursor, 0xc8u);
        store_eax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
    {
        load_rax(cursor, value_slot(operands.a, function));
        emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x80u);
        emit_u32(cursor, 0u - operands.b * operands.c);
        store_eax(cursor, result_slot);
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
        load_eax(cursor, value_slot(operands.b, function));
        load_ecx(cursor, value_slot(operands.c, function));
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
        store_eax(cursor, result_slot);
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
        load_eax(cursor, value_slot(operands.b, function));
        load_ecx(cursor, value_slot(operands.c, function));
        emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, setcc_opcode(operands.a)); emit_u8(cursor, 0xc0u);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u); emit_u8(cursor, 0xc0u);
        store_eax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_UNARY)
    {
        load_eax(cursor, value_slot(operands.b, function));
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
        store_eax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_RETURN || core.op == X86_LIR_OP_RETURN_VOID)
    {
        if (operands.a == INVALID || core.op == X86_LIR_OP_RETURN_VOID)
        { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xc0u); }
        else if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
            load_rax(cursor, value_slot(operands.a, function));
        else load_eax(cursor, value_slot(operands.a, function));
        emit_u8(cursor, 0xc9u); emit_u8(cursor, 0xc3u);
    }
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        bool aggregate_reference =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        if (aggregate_reference)
        {
            load_rax(cursor, value_slot(operands.a, function));
            move_rax_to_argument(cursor, operands.b);
        }
        else
        {
            load_eax(cursor, value_slot(operands.a, function));
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
            store_rax(cursor, result_slot);
        else store_eax(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_CALL_HOST && operands.a == 28u)
    {
        // The preceding CALL_ARG row placed the signed i32 in EDI. Convert it
        // directly and retain the f32 result in the ordinary value-slot domain.
        emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x0fu);
        emit_u8(cursor, 0x2au); emit_u8(cursor, 0xc7u);
        store_xmm0(cursor, result_slot);
    }
    else if (core.op == X86_LIR_OP_CALL_HOST && operands.a == 29u)
    {
        // The preceding CALL_ARG row has placed the status in EDI.
        emit_u8(cursor, 0xb8u); emit_u32(cursor, 60u);
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x05u);
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
            load_eax(cursor, value_slot(operands.a, function));
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
    uint main_pos = layout.body_offset + layout.entrypoint_body_offset;
    emit_u8(cursor, 0xe8u); emit_u32(cursor, main_pos - cursor - 4u);
    emit_u8(cursor, 0x89u); emit_u8(cursor, 0xc7u);
    emit_u8(cursor, 0xb8u); emit_u32(cursor, 60u);
    emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x05u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    if (layout.status != 0u || row >= total) return;
    if (row == 0u) emit_header_and_wrapper(layout);
    uint function_id = scheduled_function_id[row];
    uint semantic_function_count = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    if (function_id >= semantic_function_count) return;
    uint function_index = target_function_index_by_semantic[function_id];
    if (function_index >= target_function_count[0u]) return;
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    uint cursor = layout.body_offset + target_byte_offset[row];
    if (row == function.instruction_start) emit_prologue(cursor, function, semantic_function);
    emit_instruction(cursor, target_lir_core[row], target_lir_operands[row], function, layout);
    if (row + 1u == function.instruction_start + function.instruction_count) emit_footer(cursor);
}
