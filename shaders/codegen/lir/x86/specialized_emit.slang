import codegen.lir.x86.emission_common;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.safety;
import gpu_index;

bool x86_is_specialized_instruction(X86LirCore core,
                                   X86LirOperands operands)
{
    return (operands.metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u ||
        ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u &&
         (core.op == X86_LIR_OP_COMPARE ||
          core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE ||
          core.op == X86_LIR_OP_SELECT_STORE)) ||
        (operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u ||
        (core.op == X86_LIR_OP_CALL_ARG &&
         (operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u) ||
        (core.op == X86_LIR_OP_FIELD_STORE &&
         (operands.metadata & X86_LIR_METADATA_FIELD_AGGREGATE_WORD) != 0u) ||
        (core.op == X86_LIR_OP_STORE_LOCAL &&
         (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u) ||
        core.op == X86_LIR_OP_INTRINSIC_SLICE_FROM_RAW_PARTS ||
        ((core.op == X86_LIR_OP_INDEX_LOAD ||
          core.op == X86_LIR_OP_INDEX_STORE) &&
         (operands.metadata & 0xffu) == 3u);
}

uint aggregate_setcc_opcode(uint predicate)
{
    if (predicate == 0u) return 0x94u;
    if (predicate == 1u) return 0x95u;
    if (predicate == 2u) return 0x9cu;
    if (predicate == 3u) return 0x9fu;
    if (predicate == 4u) return 0x9eu;
    return 0x9du;
}

void emit_aggregate_word_compare(inout uint cursor, uint left, uint right,
                                 TargetLirFunction function)
{
    // One-word aggregates use address-valued operands. Compare the stored
    // word (an enum discriminant), not the two unrelated addresses.
    load_value64(cursor, left, 0u, function);
    load_value64(cursor, right, 1u, function);
    emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x00u); // mov eax, [rax]
    emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x09u); // mov ecx, [rcx]
    emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u); // cmp eax, ecx
}

void emit_specialized_instruction(inout uint cursor, X86LirCore core,
                                 X86LirOperands operands,
                                 X86LirLocations locations,
                                 TargetLirFunction function)
{
    if (core.op == X86_LIR_OP_COMPARE)
    {
        emit_aggregate_word_compare(cursor, locations.b, locations.c,
            function);
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, aggregate_setcc_opcode(operands.a));
        emit_u8(cursor, 0xc0u); // setcc al
        emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u);
        emit_u8(cursor, 0xc0u); // movzx eax, al
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        emit_aggregate_word_compare(cursor, locations.a, locations.b,
            function);
        uint target = x86_artifact_layout[0u].body_offset +
            target_byte_offset[core.result_or_target];
        uint next = cursor + 6u;
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, (aggregate_setcc_opcode(core.local_ordinal) ^ 1u)
            - 0x10u);
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
        emit_aggregate_word_compare(cursor, locations.a, locations.b,
            function);
        load_value32(cursor, locations.c, 0u, function);
        if (selected_register >= 8u) emit_u8(cursor, 0x44u);
        emit_u8(cursor, 0x0fu);
        emit_u8(cursor, aggregate_setcc_opcode(core.local_ordinal) - 0x50u);
        emit_u8(cursor, 0xc0u | ((selected_register & 7u) << 3u));
        if (!register_destination)
            store_value32(cursor, 2u, destination, function);
    }
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        if (operands.b >= 6u && core.local_ordinal != 0u)
            emit_u32(cursor, 0x08ec8348u); // sub rsp, 8
        uint destination = X86_LOCATION_REGISTER |
            (operands.b >= 6u ? 0u : x86_abi_argument_register(operands.b));
        // FIELD_LOAD yields the address of the in-struct slice pair.
        // Load its selected word before placing it in the ABI argument slot.
        load_value64(cursor, locations.a, 0u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x80u);
        emit_u32(cursor, 0u - operands.c * 8u);
        if (operands.c == 0u)
            move_location64(cursor, X86_LOCATION_REGISTER, destination);
        else
            move_location32(cursor, X86_LOCATION_REGISTER, destination);
        if (operands.b >= 6u) emit_u8(cursor, 0x50u); // push rax
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value64(cursor, locations.c, 1u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
        if (core.local_ordinal == 0u)
            emit_u8(cursor, 0x09u);
        else
        {
            emit_u8(cursor, 0x89u);
            emit_u32(cursor, 0u - core.local_ordinal * 8u);
        }
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
        emit_u32(cursor, 0u - operands.b * (operands.metadata >> 24u));
    }
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        if ((operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u)
        {
            // Slice-producing expressions yield a pointer to two-word
            // temporary storage. Declaration homes, including parameter
            // homes, hold those two words directly.
            uint destination = declaration_location(operands.a);
            load_value64(cursor, locations.b, 0u, function);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x08u);
            store_declaration64(cursor, 1u, destination);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x88u);
            emit_u32(cursor, 0xfffffff8u);
            store_declaration64(cursor, 1u, destination + 1u);
        }
        else
        {
            uint base_slot = value_slot(locations.result, function) + operands.c;
            emit_stack_address(cursor, 0u, base_slot);
            store_declaration64(cursor, 0u, declaration_location(operands.a));
        }
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_ADDR)
    {
        uint base_slot = value_slot(locations.result, function) + operands.c;
        emit_stack_address(cursor, 0u, base_slot);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_INIT)
    {
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
        {
            emit_u8(cursor, 0xb8u);
            emit_u32(cursor, operands.a);
        }
        else load_value32(cursor, locations.a, 0u, function);
        uint word = core.local_ordinal - 1u;
        uint allocation_slot = x86_location_payload(locations.result) -
            core.local_ordinal;
        store_stack_packed_i32(cursor, 0u,
            allocation_slot + operands.c, word);
    }
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        load_value64(cursor, locations.a, 0u, function);
        if ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
            emit_u8(cursor, 0x00u); // mov rax, [rax]
        }
        load_value32(cursor, locations.b, 1u, function);
        emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x04u); emit_u8(cursor, 0x88u);
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        if ((operands.metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u)
        {
            uint words = core.result_or_target;
            emit_u8(cursor, 0x57u); // push rdi
            emit_u8(cursor, 0x56u); // push rsi
            load_value64(cursor, locations.a, 0u, function);
            if ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
            {
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
                emit_u8(cursor, 0x00u); // mov rax, [rax]
            }
            load_value32(cursor, locations.b, 1u, function);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0xf7u);
            emit_u8(cursor, 0xd9u); // neg rcx
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x69u);
            emit_u8(cursor, 0xc9u);
            emit_u32(cursor, words * 8u); // imul rcx, rcx, element bytes
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du);
            emit_u8(cursor, 0x04u); emit_u8(cursor, 0x08u);
            load_value64(cursor, locations.c, 2u, function);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x39u);
            emit_u8(cursor, 0xd0u); // cmp rax, rdx
            emit_u8(cursor, 0x76u); emit_u8(cursor, 18u); // jbe forward
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u);
            emit_u8(cursor, 0xc7u); // mov rdi, rax
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u);
            emit_u8(cursor, 0xd6u); // mov rsi, rdx
            emit_u8(cursor, 0xb9u); emit_u32(cursor, words); // mov ecx, words
            emit_u8(cursor, 0xfdu); // std
            emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0xa5u); // rep movsq
            emit_u8(cursor, 0xfcu); // cld
            emit_u8(cursor, 0xebu); emit_u8(cursor, 23u); // jmp done
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du);
            emit_u8(cursor, 0xb8u);
            emit_u32(cursor, 0u - (words - 1u) * 8u);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du);
            emit_u8(cursor, 0xb2u);
            emit_u32(cursor, 0u - (words - 1u) * 8u);
            emit_u8(cursor, 0xb9u); emit_u32(cursor, words);
            emit_u8(cursor, 0xfcu); // cld
            emit_u8(cursor, 0xf3u); emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0xa5u); // rep movsq
            emit_u8(cursor, 0x5eu); // pop rsi
            emit_u8(cursor, 0x5fu); // pop rdi
        }
        else
        {
            load_value64(cursor, locations.a, 0u, function);
            if ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
            {
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
                emit_u8(cursor, 0x00u); // mov rax, [rax]
            }
            load_value32(cursor, locations.b, 1u, function);
            load_value32(cursor, locations.c, 2u, function);
            emit_u8(cursor, 0x89u); emit_u8(cursor, 0x14u); emit_u8(cursor, 0x88u);
        }
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_COPY_WORD)
    {
        load_value64(cursor, locations.a, 0u, function);
        uint byte_offset = operands.b * 4u;
        emit_u8(cursor, 0x8bu);
        if (byte_offset == 0u)
            emit_u8(cursor, 0x08u);
        else if (byte_offset <= 0x7fu)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, byte_offset);
        }
        else
        {
            emit_u8(cursor, 0x88u); emit_u32(cursor, byte_offset);
        }
        uint allocation_slot = x86_location_payload(locations.result) -
            operands.b - 1u;
        store_stack_packed_i32(cursor, 1u,
            allocation_slot + operands.c, operands.b);
    }
    else if (core.op == X86_LIR_OP_INTRINSIC_SLICE_FROM_RAW_PARTS)
    {
        // The preceding CALL_ARG rows placed data in RDI and length in RSI.
        // Normalize the signed-i32 length to an unsigned machine word before
        // publishing the native pointer-and-length pair.
        uint storage_slot = value_slot(locations.result, function) + 1u;
        store_stack64(cursor, 7u, storage_slot);
        emit_u8(cursor, 0x89u); emit_u8(cursor, 0xf6u); // mov esi, esi
        store_stack64(cursor, 6u, storage_slot + 1u);
        emit_stack_address(cursor, 0u, storage_slot);
        store_value64(cursor, 0u, locations.result, function);
    }
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
    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    if (!x86_is_specialized_instruction(core, operands)) return;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    if (layout.status != 0u) return;
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
        cursor += prologue_bytes(function, semantic_function, saved_mask);
    cursor += x86_safety_guard_bytes(core, operands,
        target_lir_locations[page_row]);
    emit_specialized_instruction(cursor, core, operands,
        target_lir_locations[page_row], function);
}
