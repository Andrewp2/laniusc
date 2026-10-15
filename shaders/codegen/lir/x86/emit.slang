import primitive_types;
import native_value_layout;
import codegen.lir.x86.emission_common;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.frame_layout;
import codegen.lir.x86.safety;
import codegen.lir.x86.encoding;
import codegen.lir.x86.instruction_plan;
import gpu_index;

// Writes every target row's body and implicit footer (ordinary and
// specialized alike) from the shared instruction plan, plus the ELF header,
// entry wrapper and rodata. Prologues and guards are written by safety_emit.

uint resolve_plan_word(X86PlanOp op, uint cursor, X86ArtifactLayout layout)
{
    uint mode = (op.head >> 13u) & 7u;
    uint value = op.b;
    if (mode == X86_RESOLVE_ROW) value = layout.body_offset + target_byte_offset[value];
    else if (mode == X86_RESOLVE_RUNTIME) value = layout.runtime_offset + value;
    else if (mode == X86_RESOLVE_STRING_ADDR)
        value = ELF_BASE_VADDR + layout.rodata_offset + semantic_lir_strings[value].data_offset;
    else if (mode == X86_RESOLVE_STRING_LEN) value = semantic_lir_strings[value].decoded_len;
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
    X86LirOperands operands = target_lir_operands[page_row];
    X86LirLocations locations = target_lir_locations[page_row];
    uint cursor = layout.body_offset + target_byte_offset[row];
    if (row == function.instruction_start)
        cursor += prologue_bytes(function, semantic_function, saved_mask);
    cursor += x86_safety_guard_bytes(core, operands, locations);

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
    input.specialized = x86_is_specialized_instruction(core, operands);
    bool final_explicit_return = core.op == X86_LIR_OP_RETURN ||
        core.op == X86_LIR_OP_RETURN_VOID || core.op == X86_LIR_OP_TRAP;
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
        if (x86_op_kind(op.head) == X86_OP_BYTES) op.b = resolve_plan_word(op, cursor, layout);
        X86Code code = x86_encode(op);
        for (uint i = 0u; i < code.length; i += 1u)
            store_byte(cursor + i, x86_code_byte(code, i));
        cursor += code.length;
    }
}
