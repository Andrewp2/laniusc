import primitive_types;
import native_value_layout;
import codegen.lir.x86.emission_common;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.frame_layout;
import codegen.lir.x86.safety;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.encoding;
import codegen.lir.x86.instruction_plan;
import gpu_index;

// Writes every target row's body and implicit footer (ordinary and
// specialized alike) from the shared instruction plan, plus the ELF header,
// entry wrapper and rodata. Prologues and guards are written by safety_emit.
//
// Each row also records its one native-runtime reference (a guard's trap jcc
// or a runtime call): x = text-relative rel32 site + 1 (0 = none), y =
// relocation kind << 16 | runtime offset. The object stage turns these into
// relocations so a link can keep a single runtime copy.
RWStructuredBuffer<uint2> x86_runtime_reference;
RWStructuredBuffer<uint> x86_runtime_reference_flag;

static const uint X86_RUNTIME_REFERENCE_REL32 = 1u;
static const uint X86_RUNTIME_REFERENCE_CALL_REL32 = 2u;
// Not a runtime reference: the rel32 of the jump over a C entry's load of the
// process vector (instruction_plan.slang, plan_c_entry). y = kind << 16 | the
// displacement a raw link writes. A native link leaves the 0 in place.
static const uint X86_RUNTIME_REFERENCE_RAW_REL32 = 4u;

// The runtime trap a row's guard branches to, or 0xffffffff. Every trap guard
// ends in its jcc or jmp rel32 (safety_emit.emit_guards).
uint x86_guard_trap_offset(X86LirCore core, X86LirOperands operands)
{
    if ((core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE ||
         core.op == X86_LIR_OP_INDEX_ADDRESS) && core.local_ordinal != 0xffffffffu)
        return X86_RUNTIME_TRAP_BOUNDS_OFFSET;
    if (x86_safety_shift(core, operands)) return X86_RUNTIME_TRAP_SHIFT_OFFSET;
    if (x86_safety_integer_division(core, operands)) return X86_RUNTIME_TRAP_DIVIDE_OFFSET;
    return 0xffffffffu;
}

uint resolve_plan_word(X86PlanOp op, uint cursor, X86ArtifactLayout layout)
{
    uint mode = (op.head >> 13u) & 7u;
    uint value = op.b;
    if (mode == X86_RESOLVE_ROW) value = layout.body_offset + target_byte_offset[value];
    else if (mode == X86_RESOLVE_RUNTIME) value = layout.runtime_offset + value;
    else if (mode == X86_RESOLVE_STRING_ADDR)
        value = ELF_BASE_VADDR + layout.rodata_offset + semantic_lir_strings[value].data_offset;
    else if (mode == X86_RESOLVE_STRING_LEN) value = semantic_lir_strings[value].decoded_len;
    // No object is projected: the artifact is a raw executable.
    else if (mode == X86_RESOLVE_RAW_ONLY && gParams.runtime_reference_capacity != 0u) value = 0u;
    if (((op.head >> 16u) & 1u) != 0u) value -= cursor + x86_bytes_op_length(op.head);
    return value;
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
    // exit_group (231), not exit (60): every thread of the process ends.
    emit_u8(cursor, 0xb8u); emit_u32(cursor, 231u);
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
    // An executable build binds one-row reference buffers and records none.
    bool record_runtime_reference = row < gParams.runtime_reference_capacity;
    uint2 runtime_reference = uint2(0u, 0u);
    if (record_runtime_reference)
    {
        x86_runtime_reference[row] = runtime_reference;
        x86_runtime_reference_flag[row] = 0u;
    }
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
    X86LirOperands operands = target_lir_operands[page_row];
    X86LirLocations locations = target_lir_locations[page_row];
    uint cursor = layout.body_offset + target_byte_offset[row];
    if (row == function.instruction_start)
        cursor += prologue_bytes(function, semantic_function, saved_mask);
    cursor += x86_safety_guard_bytes(core, operands, locations);
    uint guard_trap = x86_guard_trap_offset(core, operands);
    if (guard_trap != 0xffffffffu)
        runtime_reference = uint2(cursor - 4u - layout.text_offset + 1u,
            (X86_RUNTIME_REFERENCE_REL32 << 16u) | guard_trap);

    X86PlanInput input;
    input.core = core;
    input.operands = operands;
    input.locations = locations;
    input.hidden_sret_slot = function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
    input.saved_first_slot = base_frame_slots(function, semantic_function);
    input.saved_mask = saved_mask;
    input.frameless = frameless_function(function, semantic_function);
    input.stackless = stackless_caller(function, semantic_function);
    input.decl_a = declaration_location(operands.a);
    input.decl_target = declaration_location(core.result_or_target);
    input.place_slot = operands.a < gParams.token_capacity
        ? x86_place_storage_by_token[operands.a].x : 0u;
    input.callee_row = INVALID;
    if (core.op == X86_LIR_OP_CALL)
    {
        uint callee_index = operands.a < gParams.function_capacity
            ? target_function_index_by_semantic[operands.a] : INVALID;
        if (callee_index < target_function_count[0u])
            input.callee_row = target_functions[callee_index].instruction_start;
    }
    input.c_entry_narrow_mask = 0u;
    if (core.op == X86_LIR_OP_CALL && (operands.metadata & X86_LIR_METADATA_NATIVE_C) != 0u &&
        operands.a < semantic_function_count)
    {
        SemanticLirFunction callee = semantic_lir_functions[operands.a];
        for (uint ordinal = 0u; ordinal < min(callee.param_count, 6u); ordinal++)
        {
            uint type = semantic_lir_params[callee.param_start + ordinal].type_id;
            if (type == SCALAR_I32 || type == SCALAR_U32) input.c_entry_narrow_mask |= 1u << ordinal;
        }
    }
    input.specialized = x86_is_specialized_instruction(core, operands);
    bool final_explicit_return = core.op == X86_LIR_OP_RETURN ||
        core.op == X86_LIR_OP_RETURN_VOID || core.op == X86_LIR_OP_TRAP ||
        (core.op == X86_LIR_OP_SELECT_STORE &&
         (operands.metadata & X86_LIR_METADATA_SELECT_RETURN) != 0u);
    input.footer = row + 1u == function.instruction_start + function.instruction_count &&
        !final_explicit_return;
    // Rows naming a missing string keep their counted bytes but write none.
    input.skip_body = !input.specialized &&
        (core.op == X86_LIR_OP_STRING_ADDR || core.op == X86_LIR_OP_STRING_LEN) &&
        operands.a >= min(gParams.token_capacity, semantic_lir_string_total[0u]);

    for (uint step = 0u; ; step += 1u)
    {
        X86PlanOp op = x86_plan(input, step);
        if (x86_op_kind(op.head) == X86_OP_END) break;
        if (x86_op_kind(op.head) == X86_OP_BYTES)
        {
            // A runtime target is the op's one trailing rel32 word (plan_jump).
            uint mode = (op.head >> 13u) & 7u;
            if (mode == X86_RESOLVE_RUNTIME || mode == X86_RESOLVE_RAW_ONLY)
                runtime_reference = uint2(
                    cursor + x86_bytes_op_length(op.head) - 4u - layout.text_offset + 1u,
                    ((mode == X86_RESOLVE_RUNTIME ? X86_RUNTIME_REFERENCE_CALL_REL32
                        : X86_RUNTIME_REFERENCE_RAW_REL32) << 16u) | op.b);
            op.b = resolve_plan_word(op, cursor, layout);
        }
        X86Code code = x86_encode(op);
        for (uint i = 0u; i < code.length; i += 1u)
            store_byte(cursor + i, x86_code_byte(code, i));
        cursor += code.length;
    }
    if (record_runtime_reference && runtime_reference.x != 0u)
    {
        x86_runtime_reference[row] = runtime_reference;
        x86_runtime_reference_flag[row] = 1u;
    }
}
