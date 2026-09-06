import codegen.lir.x86.emission_common;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.safety;
import gpu_index;

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
            abi_ordinal += x86_abi_param_width(
                semantic_lir_params[semantic_function.param_start + prior]);
        uint width = x86_abi_param_width(param);
        uint destination = declaration_location(param.declaration_id);
        for (uint component = 0u; component < width; component += 1u)
        {
            uint incoming = abi_ordinal + component;
            if (incoming >= 6u)
            {
                // Stack arguments begin above the return address (and saved RBP).
                uint displacement = (incoming - 6u) * 8u + (frameless ? 8u : 16u);
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
                emit_u8(cursor, frameless || stackless ? 0x84u : 0x85u);
                if (frameless || stackless) emit_u8(cursor, 0x24u);
                emit_u32(cursor, displacement);
            }
            store_declaration64(cursor, incoming < 6u ? x86_abi_argument_register(incoming) : 0u,
                destination + component);
        }
    }
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
        if (core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
        {
            load_value32(cursor, locations.length, 0u, function);
            emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc1u);
        }
        else
        {
            emit_u8(cursor, 0x81u); emit_u8(cursor, 0xf9u);
            emit_u32(cursor, core.local_ordinal);
        }
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
        emit_prologue(cursor, function, semantic_function, saved_mask);
    emit_guards(cursor, core, operands, locations, function);
}
