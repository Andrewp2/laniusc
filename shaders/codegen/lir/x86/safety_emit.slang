import primitive_types;
import codegen.lir.x86.emission_common;
import codegen.lir.x86.frame_layout;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.safety;
import codegen.lir.x86.parameter_values;
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
    // Fresh parameter cells own aggregate values. Descriptor parameters have
    // no copied backing bytes; their saved pointer/length components retain
    // the original aliases. All incoming arguments have been saved above.
    uint copy_slot = (function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK) -
        x86_parameter_storage_total(semantic_function, semantic_lir_params);
    for (uint ordinal = 0u; ordinal < semantic_function.param_count; ordinal++)
    {
        uint row = semantic_function.param_start + ordinal;
        uint words = x86_parameter_value_words(row);
        uint declaration = semantic_lir_params[row].declaration_id;
        uint storage = x86_parameter_storage_words(row, declaration);
        if (storage == 0u) continue;
        bool packed = x86_parameter_home_is_packed(row, declaration);
        uint base_slot = copy_slot + (packed ? storage - 1u : 0u);
        uint home = declaration_location(semantic_lir_params[row].declaration_id);
        if (words == 0u)
        {
            emit_stack_address(cursor, 7u, base_slot);
            store_stack64(cursor, 7u, home);
            copy_slot += storage;
            continue;
        }
        load_stack64(cursor, home, 6u); // RSI: incoming storage
        emit_stack_address(cursor, 7u, base_slot); // RDI: fresh parameter value
        store_stack64(cursor, 7u, home);
        if (x86_parameter_is_packed(row) && !packed)
        {
            for (uint word = 0u; word < words; word++)
            {
                emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x86u);
                emit_u32(cursor, word * 4u); // mov eax,[rsi+word*4]
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x87u);
                emit_u32(cursor, 0u - word * 8u); // mov [rdi-word*8],rax
            }
            copy_slot += storage;
            continue;
        }
        if (!packed && words > 1u)
        {
            // Native values descend by words. Move from each lowest address
            // with DF clear, preserving the native first-word address in home.
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x81u); emit_u8(cursor, 0xeeu);
            emit_u32(cursor, (words - 1u) * 8u); // sub rsi, extent
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x81u); emit_u8(cursor, 0xefu);
            emit_u32(cursor, (words - 1u) * 8u); // sub rdi, extent
        }
        emit_u8(cursor, 0xb9u); emit_u32(cursor, words); // mov ecx, words
        emit_u8(cursor, 0xf3u);
        if (!packed) emit_u8(cursor, 0x48u);
        emit_u8(cursor, 0xa5u); // rep movsd/movsq
        copy_slot += storage;
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
    bool rhs_wide = (operands.metadata & X86_LIR_METADATA_RHS_NARROW) == 0u;
    uint type = operands.metadata & 0xffu;
    if ((core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE ||
         core.op == X86_LIR_OP_INDEX_ADDRESS) && core.local_ordinal != 0xffffffffu)
    {
        if (rhs_wide) load_value64(cursor, locations.b, 1u, function);
        else load_value32(cursor, locations.b, 1u, function);
        if (core.local_ordinal == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
        {
            if ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
            {
                load_value64(cursor, locations.a, 0u, function);
                emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x40u);
                emit_u8(cursor, 0xf8u); // mov eax, [rax - 8], zero-extended bound
            }
            else load_value32(cursor, locations.length, 0u, function);
            if (rhs_wide) emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc1u);
        }
        else if (rhs_wide)
        {
            // CMP r64, imm32 sign-extends its immediate; materialize the u32
            // resource bound first so high-bit lengths remain unsigned.
            emit_u8(cursor, 0xb8u); emit_u32(cursor, core.local_ordinal);
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc1u);
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
        if (rhs_wide) load_value64(cursor, locations.c, 1u, function);
        else load_value32(cursor, locations.c, 1u, function);
        uint bits = scalar_integer_bits(type);
        if (rhs_wide) emit_u8(cursor, 0x48u);
        emit_u8(cursor, 0x83u); emit_u8(cursor, 0xf9u); emit_u8(cursor, bits == 0u ? 31u : bits - 1u);
        emit_u8(cursor, 0x76u); emit_u8(cursor, 12u);
        emit_exit(cursor, 102u);
        return;
    }
    if (!x86_safety_integer_division(core, operands)) return;
    bool wide = scalar_is_wide_integer(type);
    if (wide) load_value64(cursor, locations.c, 1u, function);
    else load_value32(cursor, locations.c, 1u, function);
    if (wide) emit_u8(cursor, 0x48u);
    emit_u8(cursor, 0x85u); emit_u8(cursor, 0xc9u);
    emit_u8(cursor, 0x75u); emit_u8(cursor, 12u);
    emit_exit(cursor, 103u);
    if (!scalar_is_signed_integer(type)) return;
    uint lhs_load_bytes = wide ? x86_move64_to_fixed_bytes(locations.b, 0u)
        : x86_move32_to_fixed_bytes(locations.b, 0u);
    if (wide) emit_u8(cursor, 0x48u);
    emit_u8(cursor, 0x83u); emit_u8(cursor, 0xf9u); emit_u8(cursor, 0xffu);
    emit_u8(cursor, 0x75u); emit_u8(cursor, lhs_load_bytes + (wide ? 27u : 19u));
    if (wide)
    {
        load_value64(cursor, locations.b, 0u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xbau);
        emit_u64(cursor, 0u, 0x80000000u); // movabs rdx, I64_MIN
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x39u); emit_u8(cursor, 0xd0u);
    }
    else
    {
        load_value32(cursor, locations.b, 0u, function);
        emit_u8(cursor, 0x3du);
        emit_u32(cursor, 0u - (1u << (scalar_integer_bits(type) - 1u)));
    }
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
