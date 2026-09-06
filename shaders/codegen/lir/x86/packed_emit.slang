import codegen.lir.x86.emission_common;
import codegen.lowering_ir;
import codegen.lir.x86.location_common;
import codegen.lir.x86.safety;
import gpu_index;

bool x86_is_packed_i32_instruction(X86LirCore core,
                                   X86LirOperands operands)
{
    return (operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u ||
        (core.op == X86_LIR_OP_STORE_LOCAL &&
         (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u) ||
        core.op == X86_LIR_OP_INTRINSIC_SLICE_FROM_RAW_PARTS ||
        ((core.op == X86_LIR_OP_INDEX_LOAD ||
          core.op == X86_LIR_OP_INDEX_STORE) &&
         (operands.metadata & 0xffu) == 3u);
}

void emit_packed_i32_instruction(inout uint cursor, X86LirCore core,
                                 X86LirOperands operands,
                                 X86LirLocations locations,
                                 TargetLirFunction function)
{
    if (core.op == X86_LIR_OP_STORE_LOCAL)
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
        load_value32(cursor, locations.b, 1u, function);
        emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x04u); emit_u8(cursor, 0x88u);
        store_value32(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        load_value32(cursor, locations.b, 1u, function);
        load_value32(cursor, locations.c, 2u, function);
        emit_u8(cursor, 0x89u); emit_u8(cursor, 0x14u); emit_u8(cursor, 0x88u);
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
    if (!x86_is_packed_i32_instruction(core, operands)) return;
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
    emit_packed_i32_instruction(cursor, core, operands,
        target_lir_locations[page_row], function);
}
