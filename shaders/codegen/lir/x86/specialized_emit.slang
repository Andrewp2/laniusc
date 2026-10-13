import primitive_types;
import native_value_layout;
import codegen.lir.x86.index_address;
import codegen.lir.x86.place_emit;
import codegen.lir.x86.emission_common;
import codegen.lir.x86.frame_layout;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.storage_layout;
import codegen.lir.x86.location_common;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.safety;
import gpu_index;

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

// Arithmetic for the newly distinct integer widths uses fixed scratch GPRs.
// Existing i32/u32 register/immediate fast paths remain unchanged below.
void emit_integer_width_normalize(inout uint cursor, uint type)
{
    uint bits = scalar_integer_bits(type);
    if (bits != 8u && bits != 16u) return;
    emit_u8(cursor, 0x0fu);
    emit_u8(cursor, scalar_is_signed_integer(type)
        ? (bits == 8u ? 0xbeu : 0xbfu) : (bits == 8u ? 0xb6u : 0xb7u));
    emit_u8(cursor, 0xc0u); // movsx/movzx eax, al/ax
}

void emit_integer_width_binary(inout uint cursor, X86LirOperands operands,
    X86LirLocations locations, TargetLirFunction function)
{
    uint type = operands.metadata & 0xffu;
    bool wide = scalar_is_wide_integer(type);
    bool shift = operands.a == X86_LIR_BINARY_SHL_I32 || operands.a == X86_LIR_BINARY_SHR_I32;
    if (wide) load_value64(cursor, locations.b, 0u, function);
    else load_value32(cursor, locations.b, 0u, function);
    if (wide && (!shift || (operands.metadata & X86_LIR_METADATA_RHS_NARROW) == 0u))
        load_value64(cursor, locations.c, 1u, function);
    else load_value32(cursor, locations.c, 1u, function);
    if (operands.a == X86_LIR_BINARY_DIV_I32 || operands.a == X86_LIR_BINARY_REM_I32)
    {
        if (scalar_is_signed_integer(type))
        {
            if (wide) emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0x99u); // cdq/cqo
        }
        else { emit_u8(cursor, 0x31u); emit_u8(cursor, 0xd2u); }
        if (wide) emit_u8(cursor, 0x48u);
        emit_u8(cursor, 0xf7u);
        emit_u8(cursor, scalar_is_signed_integer(type) ? 0xf9u : 0xf1u);
        if (operands.a == X86_LIR_BINARY_REM_I32)
        {
            if (wide) emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0x89u); emit_u8(cursor, 0xd0u);
        }
    }
    else
    {
        if (wide) emit_u8(cursor, 0x48u);
        if (operands.a == X86_LIR_BINARY_MUL_I32)
        { emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xafu); emit_u8(cursor, 0xc1u); }
        else if (shift)
        {
            emit_u8(cursor, 0xd3u);
            emit_u8(cursor, operands.a == X86_LIR_BINARY_SHL_I32 ? 0xe0u
                : scalar_is_signed_integer(type) ? 0xf8u : 0xe8u);
        }
        else
        {
            emit_u8(cursor, operands.a == X86_LIR_BINARY_ADD_I32 ? 0x01u :
                operands.a == X86_LIR_BINARY_SUB_I32 ? 0x29u :
                operands.a == X86_LIR_BINARY_BIT_AND_I32 ? 0x21u :
                operands.a == X86_LIR_BINARY_BIT_OR_I32 ? 0x09u : 0x31u);
            emit_u8(cursor, 0xc8u);
        }
    }
    emit_integer_width_normalize(cursor, type);
    if (wide) store_value64(cursor, 0u, locations.result, function);
    else store_value32(cursor, 0u, locations.result, function);
}

// Emission and counting use x86_is_specialized_float_instruction as their
// sole body ownership predicate. No prologue, guard or footer is moved here.
void emit_float_instruction(inout uint cursor, X86LirCore core,
    X86LirOperands operands, X86LirLocations locations, TargetLirFunction function)
{
    bool wide = x86_scalar_f64(operands.metadata);
    if (core.op == X86_LIR_OP_BINARY)
        emit_float_binary(cursor, operands.a, locations.b, locations.c, locations.result, wide);
    else if (core.op == X86_LIR_OP_UNARY)
    {
        move_float_to_gpr(cursor, locations.b, 0u, wide);
        if (wide)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x0fu);
            emit_u8(cursor, 0xbau); emit_u8(cursor, 0xf8u); emit_u8(cursor, 63u);
        }
        else { emit_u8(cursor, 0x35u); emit_u32(cursor, 0x80000000u); }
        move_float_from_gpr(cursor, 0u, locations.result, wide);
    }
    else
    {
        bool branch = core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE;
        emit_float_compare(cursor, branch ? locations.a : locations.b,
            branch ? locations.b : locations.c, wide);
        emit_float_predicate_al(cursor, branch ? core.local_ordinal : operands.a);
        if (branch)
        {
            emit_u8(cursor, 0x84u); emit_u8(cursor, 0xc0u); // TEST AL, AL
            uint target = x86_artifact_layout[0u].body_offset + target_byte_offset[core.result_or_target];
            uint next = cursor + 6u;
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0x84u);
            emit_u32(cursor, target - next);
        }
        else
        {
            emit_u8(cursor, 0x0fu); emit_u8(cursor, 0xb6u); emit_u8(cursor, 0xc0u);
            store_value32(cursor, 0u, locations.result, function);
        }
    }
}

void emit_specialized_instruction(inout uint cursor, X86LirCore core,
                                 X86LirOperands operands,
                                 X86LirLocations locations,
                                 TargetLirFunction function)
{
    uint integer_type = operands.metadata & 0xffu;
    bool distinct_integer_width = scalar_is_wide_integer(integer_type) || scalar_is_narrow_integer(integer_type);
    if (core.op == X86_LIR_OP_IMM_I64)
    {
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xb8u);
        emit_u64(cursor, operands.a, operands.b);
        if (x86_scalar_f64(operands.metadata))
            move_float_from_gpr(cursor, 0u, locations.result, true);
        else store_value64(cursor, 0u, locations.result, function);
        return;
    }
    if (x86_is_specialized_float_instruction(core, operands))
    {
        emit_float_instruction(cursor, core, operands, locations, function);
        return;
    }
    if (core.op == X86_LIR_OP_BINARY && distinct_integer_width)
    {
        emit_integer_width_binary(cursor, operands, locations, function);
        return;
    }
    if (core.op == X86_LIR_OP_UNARY && distinct_integer_width && operands.a == X86_LIR_UNARY_NEG_I32)
    {
        bool wide = scalar_is_wide_integer(integer_type);
        if (wide) load_value64(cursor, locations.b, 0u, function);
        else load_value32(cursor, locations.b, 0u, function);
        if (wide) emit_u8(cursor, 0x48u);
        emit_u8(cursor, 0xf7u); emit_u8(cursor, 0xd8u);
        emit_integer_width_normalize(cursor, integer_type);
        if (wide) store_value64(cursor, 0u, locations.result, function);
        else store_value32(cursor, 0u, locations.result, function);
        return;
    }
    if (core.op == X86_LIR_OP_BINARY && integer_type == SCALAR_PTR)
    {
        load_value64(cursor, locations.b, 0u, function);
        if (scalar_is_wide_integer(core.local_ordinal))
            load_value64(cursor, locations.c, 1u, function);
        else
        {
            load_value32(cursor, locations.c, 1u, function);
            if (scalar_is_signed_integer(core.local_ordinal))
            {
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x63u); emit_u8(cursor, 0xc9u);
            }
        }
        emit_u8(cursor, 0x48u);
        emit_u8(cursor, operands.a == X86_LIR_BINARY_SUB_I32 ? 0x29u : 0x01u);
        emit_u8(cursor, 0xc8u);
        store_value64(cursor, 0u, locations.result, function);
        return;
    }
    if ((core.op == X86_LIR_OP_COMPARE || core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE) &&
        x86_is_specialized_integer_instruction(core, operands))
    {
        bool branch = core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE;
        load_value64(cursor, branch ? locations.a : locations.b, 0u, function);
        uint right = branch ? locations.b : locations.c;
        if ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) != 0u)
            load_value32(cursor, right, 1u, function);
        else load_value64(cursor, right, 1u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x39u); emit_u8(cursor, 0xc8u);
        if (branch)
        {
            uint target = x86_artifact_layout[0u].body_offset + target_byte_offset[core.result_or_target];
            uint next = cursor + 6u;
            emit_u8(cursor, 0x0fu);
            emit_u8(cursor, integer_false_jcc_opcode(core.local_ordinal, integer_type));
            emit_u32(cursor, target - next);
        }
        else emit_boolean_result(cursor, integer_setcc_opcode(operands.a, integer_type), locations.result, function);
        return;
    }
    // Explicit place bodies share this emitter's offset/prefix contract.
    // The common partition excludes them from the ordinary emitter; guards
    // and implicit footers keep their existing separate byte ranges.
    if (core.op == X86_LIR_OP_DECL_ADDRESS)
    {
        emit_stack_address(cursor, 0u, x86_place_storage_by_token[operands.a].x);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_FIELD_ADDRESS)
    {
        load_value64(cursor, locations.a, 0u, function);
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8du); emit_u8(cursor, 0x80u);
        emit_u32(cursor, 0u - operands.b * 8u);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_INDEX_ADDRESS)
    {
        emit_index_address(cursor, core, operands, locations, function, operands.c);
        store_value64(cursor, 0u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_PLACE_LOAD)
        emit_place_load(cursor, operands, locations, function);
    else if (core.op == X86_LIR_OP_PLACE_STORE)
        emit_place_store(cursor, operands, locations, function);
    else if (core.op == X86_LIR_OP_PRINT_I32)
    {
        // Scatter accepts only print (1) and assert (2) for this opcode.
        uint target = x86_artifact_layout[0u].runtime_offset +
            (operands.a == 2u
                ? X86_RUNTIME_ASSERT_OFFSET : X86_RUNTIME_PRINT_I32_OFFSET);
        uint next = cursor + 5u;
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target - next);
    }
    else if (core.op == X86_LIR_OP_INTRINSIC_IDENTITY)
    {
        // The preceding CALL_ARG row placed the aggregate pointer in RDI.
        store_value64(cursor, 7u, locations.result, function);
    }
    else if (core.op == X86_LIR_OP_CALL || core.op == X86_LIR_OP_CALL_SYMBOL)
    {
        // Strings occupy direct pointer/length value slots. The native pair
        // return is RAX/RDX, rather than an address of aggregate storage.
        uint target = 0u;
        uint stack_bytes = x86_symbol_call_stack_bytes(core.local_ordinal);
        if (core.op == X86_LIR_OP_CALL)
        {
            uint callee_index = target_function_index_by_semantic[operands.a];
            if (callee_index >= target_function_count[0u]) return;
            TargetLirFunction callee = target_functions[callee_index];
            target = x86_artifact_layout[0u].body_offset +
                target_byte_offset[callee.instruction_start] - (cursor + 5u);
            stack_bytes = core.local_ordinal;
        }
        // An imported call retains the ordinary E8 relocation placeholder.
        emit_u8(cursor, 0xe8u); emit_u32(cursor, target);
        if (stack_bytes != 0u)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x81u); emit_u8(cursor, 0xc4u);
            emit_u32(cursor, stack_bytes);
        }
        store_value64(cursor, 0u, locations.result, function);
        store_value32(cursor, 2u, locations.result + 1u, function);
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
    {
        if ((operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
        {
            // Preserve the native aggregate return ABI while unpacking an
            // ascending i32 array into its individual native result words.
            if (operands.c <= 2u)
            {
                if (operands.b == 0u)
                {
                    load_value64(cursor, locations.a, 0u, function);
                    if (operands.c == 2u)
                    {
                        emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x50u); emit_u8(cursor, 4u);
                    }
                    emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x00u);
                }
            }
            else
            {
                load_value64(cursor, locations.a, 0u, function);
                load_stack64(cursor, function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK, 10u);
                uint offset = x86_packed_i32_element_offset(operands.b);
                emit_u8(cursor, 0x8bu);
                if (offset == 0u) emit_u8(cursor, 0x08u);
                else if (offset <= 0x7fu)
                {
                    emit_u8(cursor, 0x48u); emit_u8(cursor, offset);
                }
                else
                {
                    emit_u8(cursor, 0x88u); emit_u32(cursor, offset);
                }
                emit_u8(cursor, 0x49u); emit_u8(cursor, 0x89u);
                if (operands.b == 0u) emit_u8(cursor, 0x0au);
                else
                {
                    emit_u8(cursor, 0x8au); emit_u32(cursor, x86_native_word_displacement(operands.b));
                }
            }
        }
        else if ((operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u)
        {
            if (operands.b == NATIVE_SLICE_LENGTH) load_value32(cursor, locations.a + operands.b, 1u, function);
            else load_value64(cursor, locations.a + operands.b, 1u, function);
            load_stack64(cursor, function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK, 10u);
            emit_u8(cursor, 0x49u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x8au);
            emit_u32(cursor, x86_native_word_displacement(operands.b));
        }
        else if (operands.b == 0u)
        {
            load_value32(cursor, locations.a + 1u, 2u, function);
            load_value64(cursor, locations.a, 0u, function);
        }
    }
    else if (core.op == X86_LIR_OP_COMPARE)
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
        if (operands.c != NATIVE_SLICE_LENGTH)
            move_location64(cursor, X86_LOCATION_REGISTER, destination);
        else
            move_location32(cursor, X86_LOCATION_REGISTER, destination);
        if (operands.b >= 6u) emit_u8(cursor, 0x50u); // push rax
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        load_value64(cursor, locations.a, 0u, function);
        if ((operands.metadata & (X86_LIR_METADATA_STRING_PAIR | X86_LIR_METADATA_ARRAY_PAIR)) != 0u)
        {
            // Direct descriptors occupy adjacent value slots. They are not
            // pointers to aggregate storage, and both words belong to a store.
            if (core.local_ordinal == NATIVE_SLICE_LENGTH)
                load_value32(cursor, locations.c + core.local_ordinal, 1u, function);
            else load_value64(cursor, locations.c + core.local_ordinal, 1u, function);
        }
        else
        {
            load_value64(cursor, locations.c, 1u, function);
            if ((operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u)
            {
                // Packed local arrays ascend in four-byte elements; inline
                // fields descend in native words. The destination layout does
                // not determine the representation of the source storage.
                uint offset = core.local_ordinal * 4u;
                emit_u8(cursor, 0x8bu);
                if (offset == 0u) emit_u8(cursor, 0x09u);
                else if (offset <= 0x7fu)
                { emit_u8(cursor, 0x49u); emit_u8(cursor, offset); }
                else { emit_u8(cursor, 0x89u); emit_u32(cursor, offset); }
            }
            else
            {
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu);
                if (core.local_ordinal == 0u) emit_u8(cursor, 0x09u);
                else
                { emit_u8(cursor, 0x89u); emit_u32(cursor, 0u - core.local_ordinal * 8u); }
            }
        }
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x88u);
        emit_u32(cursor, x86_native_word_displacement(operands.b));
    }
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        if ((operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u)
        {
            uint destination = declaration_location(operands.a);
            bool indirect = (operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u;
            if (indirect) load_value64(cursor, locations.b, 0u, function);
            for (uint component = 0u; component < NATIVE_SLICE_WORDS; component++)
            {
                if (indirect)
                {
                    emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x88u);
                    emit_u32(cursor, x86_native_word_displacement(component));
                }
                else if (component == NATIVE_SLICE_LENGTH)
                    load_value32(cursor, locations.b + component, 1u, function);
                else load_value64(cursor, locations.b + component, 1u, function);
                store_declaration64(cursor, 1u, destination + component);
            }
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
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            // Packed i32 source, native word destination (e.g. an inline
            // array field). The ABI's word order is preserved by locations.c.
            load_value64(cursor, locations.a, 0u, function);
            emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x80u);
            emit_u32(cursor, x86_packed_i32_element_offset(operands.b));
            store_value64(cursor, 0u, locations.c, function);
            return;
        }
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
        bool string = (operands.metadata & 0xffu) == SEMANTIC_LIR_TY_STRING;
        bool aggregate = (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool f32 = !aggregate && (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT;
        bool packed = !aggregate && (operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u;
        emit_index_address(cursor, core, operands, locations, function, string ? 2u : aggregate ? operands.c : 1u);
        if (string)
        {
            emit_u8(cursor, 0x48u); emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x10u);
            emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x48u); emit_u8(cursor, 0xf8u);
            store_value64(cursor, 2u, locations.result, function);
            store_value32(cursor, 1u, locations.result + 1u, function);
        }
        else
        {
            if (!aggregate)
            {
                if (!packed && !f32) emit_u8(cursor, 0x48u);
                emit_u8(cursor, 0x8bu); emit_u8(cursor, 0x00u);
            }
            if (x86_scalar_float(operands.metadata)) move_float_from_gpr(cursor, 0u, locations.result, x86_scalar_f64(operands.metadata));
            else if (packed) store_value32(cursor, 0u, locations.result, function);
            else store_value64(cursor, 0u, locations.result, function);
        }
    }
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        if ((operands.metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u)
        {
            uint words = core.result_or_target;
            if (words == 0u) return; // The common safety guard still checks bounds.
            emit_u8(cursor, 0x57u); // push rdi
            emit_u8(cursor, 0x56u); // push rsi
            emit_index_address(cursor, core, operands, locations, function, words);
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
        else if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_STRING ||
            (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u)
        {
            uint words = (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u ? NATIVE_SLICE_WORDS : 2u;
            emit_index_address(cursor, core, operands, locations, function, words);
            for (uint component = 0u; component < words; component++)
            {
                if (component == 1u) load_value32(cursor, locations.c + component, 2u, function);
                else load_value64(cursor, locations.c + component, 2u, function);
                emit_u8(cursor, 0x48u); emit_u8(cursor, 0x89u); emit_u8(cursor, 0x90u);
                emit_u32(cursor, x86_native_word_displacement(component));
            }
        }
        else
        {
            emit_index_address(cursor, core, operands, locations, function, 1u);
            bool packed = (operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u;
            if (x86_scalar_float(operands.metadata)) move_float_to_gpr(cursor, locations.c, 2u, x86_scalar_f64(operands.metadata));
            else if (packed) load_value32(cursor, locations.c, 2u, function);
            else load_value64(cursor, locations.c, 2u, function);
            if (!packed) emit_u8(cursor, 0x48u);
            emit_u8(cursor, 0x89u); emit_u8(cursor, 0x10u);
        }
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_COPY_WORD)
    {
        load_value64(cursor, locations.a, 0u, function);
        uint byte_offset = (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u
            ? x86_native_word_displacement(operands.b) : x86_packed_i32_element_offset(operands.b);
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
        emit_u8(cursor, 0x48u); emit_u8(cursor, 0xc7u); emit_u8(cursor, 0xc0u); emit_u32(cursor, operands.a);
        store_stack64(cursor, 0u, storage_slot + NATIVE_SLICE_STRIDE);
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
