import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.runtime_abi;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_owner_by_instruction;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
RWStructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_next_rax_clobber_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_live_by_semantic;
RWStructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
RWStructuredBuffer<uint> x86_location_by_semantic;
StructuredBuffer<uint> x86_function_start;
StructuredBuffer<uint> x86_function_end;
RWStructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
RWStructuredBuffer<uint> x86_stack_slot_count_by_function;
RWStructuredBuffer<uint> x86_frame_slot_count_by_function;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;
RWStructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
RWStructuredBuffer<X86SelectInfo> x86_select_by_semantic;

static const uint INVALID = 0xffffffffu;
static const uint RESERVED = 0xfffffffeu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint ALLOC_REGISTER_COUNT = 8u;
static const uint ALLOC_XMM_REGISTER_COUNT = 8u;

bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || type_id == 8u;
}

bool scalar_gpr_result(SemanticLirCore core)
{
    // Compare keeps the operand representation in type_id so instruction
    // selection can choose signed, unsigned, pointer, or f32 flags. Its value
    // is nevertheless a scalar Boolean and belongs in the GPR domain.
    return semantic_lir_op(core) == SEMANTIC_LIR_OP_COMPARE ||
        scalar_gpr_type(core.type_id);
}

bool call_op(uint op)
{
    return op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_HOST ||
        op == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
        op == SEMANTIC_LIR_OP_CALL_SYMBOL;
}

bool produces_scalar_value(uint op)
{
    return op == SEMANTIC_LIR_OP_CONST_I32 ||
        op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_VALUE_GET ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
        op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
        op == SEMANTIC_LIR_OP_CONVERT || call_op(op) ||
        op == SEMANTIC_LIR_OP_ADDRESS || op == SEMANTIC_LIR_OP_LOAD ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR;
}

bool produces_f32_value(uint op)
{
    // Compare rows retain their operand type in SemanticLirCore so predicate
    // selection can distinguish f32 from integer comparison, but their value
    // is boolean. The same applies to logical operations.
    return produces_scalar_value(op) &&
        op != SEMANTIC_LIR_OP_COMPARE &&
        op != SEMANTIC_LIR_OP_LOGICAL_NOT &&
        op != SEMANTIC_LIR_OP_LOGICAL_AND &&
        op != SEMANTIC_LIR_OP_LOGICAL_OR;
}

bool supports_in_place_assignment(uint op)
{
    return op == SEMANTIC_LIR_OP_CONST_I32 ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
        op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR;
}

bool adjacent_assignment_target(uint row, uint position, uint last, uint end,
                                uint total, out uint declaration)
{
    declaration = INVALID;
    if (last != position + 1u || last >= end) return false;
    uint consumer = semantic_schedule_order[last];
    if (consumer >= total) return false;
    SemanticLirCore consumer_core = semantic_lir_core[consumer];
    uint consumer_op = semantic_lir_op(consumer_core);
    if ((consumer_op != SEMANTIC_LIR_OP_VALUE_SET &&
         consumer_op != SEMANTIC_LIR_OP_STORE) ||
        (consumer_core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                                SEMANTIC_LIR_FLAG_FIELD)) != 0u)
        return false;
    SemanticLirOperands consumer_operands = semantic_lir_operands[consumer];
    if (consumer_operands.b != row ||
        consumer_operands.a >= gParams.token_capacity)
        return false;
    declaration = consumer_operands.a;
    return true;
}

uint aggregate_copy_word_count(uint row, uint total, uint function_total)
{
    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    uint op = semantic_lir_op(core);
    if ((op != SEMANTIC_LIR_OP_VALUE_SET && op != SEMANTIC_LIR_OP_STORE) ||
        !x86_semantic_type_is_aggregate(core) || operands.b >= total)
        return 0u;
    SemanticLirCore value_core = semantic_lir_core[operands.b];
    SemanticLirOperands value_operands = semantic_lir_operands[operands.b];
    uint call_words = semantic_lir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
        value_operands.a < function_total
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
    return max(max(core.value_word_count, call_words),
        x86_aggregate_value_word_count(value_core, value_operands));
}

uint aggregate_new_word_count(SemanticLirCore core,
                              SemanticLirOperands operands)
{
    uint words = 0u;
    uint element_total = min(gParams.aggregate_capacity,
        semantic_lir_aggregate_element_total[0u]);
    for (uint element = 0u; element < operands.b; element += 1u)
    {
        uint element_row = operands.a + element;
        if (element_row >= element_total) break;
        words += semantic_lir_aggregate_elements[element_row].word_count;
    }
    return max(core.value_word_count, words);
}

uint stack_word_count(uint row, uint total, uint function_total)
{
    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    uint op = semantic_lir_op(core);
    if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        uint words = aggregate_copy_word_count(row, total, function_total);
        return words == 0u ? 0u : 1u + words;
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return 1u + aggregate_new_word_count(core, operands);
    if (op == SEMANTIC_LIR_OP_CONST_STRING ||
        (op == SEMANTIC_LIR_OP_VALUE_GET &&
         core.type_id == SEMANTIC_LIR_TY_STRING))
        return 2u;
    if (op == SEMANTIC_LIR_OP_CALL)
    {
        uint words = operands.a < function_total
            ? semantic_lir_functions[operands.a].result_word_count : 0u;
        return 1u + words;
    }
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        return 1u + core.value_word_count;
    if (op == SEMANTIC_LIR_OP_CALL_HOST)
        return operands.a == HOST_SERVICE_I32_TO_F32 ||
            x86_runtime_service_has_result(operands.a) ? 1u : 0u;
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC)
        return operands.a == INTRINSIC_I32_ARRAY_DATA_PTR ? 1u : 0u;
    return produces_scalar_value(op) ? 1u : 0u;
}

bool declaration_properties(SemanticLirFunction function, uint lane,
                            out uint declaration, out uint type_id)
{
    if (lane < function.param_count)
    {
        SemanticLirParam param =
            semantic_lir_params[function.param_start + lane];
        declaration = param.declaration_id;
        type_id = param.type_id;
        return true;
    }
    uint local = lane - function.param_count;
    if (local < function.local_count)
    {
        SemanticLirLocal value =
            semantic_lir_locals[function.local_start + local];
        declaration = value.declaration_id;
        type_id = value.type_id;
        return true;
    }
    declaration = INVALID;
    type_id = 0u;
    return false;
}

bool declaration_lane_needs_home(SemanticLirFunction function, uint lane,
                                 out uint declaration, out uint type_id)
{
    if (!declaration_properties(function, lane, declaration, type_id))
        return false;
    // Parameters are ABI homes even when the current body does not read them.
    // Locals whose initializer and reads were replaced by canonical producers
    // must not reserve a physical register that no emitted operation uses.
    if (lane < function.param_count) return true;
    if (declaration >= gParams.token_capacity) return false;
    X86DeclarationAnalysis analysis =
        x86_decl_analysis_by_token[declaration];
    uint definition_live = analysis.definition < gParams.semantic_capacity
        ? x86_live_by_semantic[analysis.definition] : 0u;
    return x86_declaration_needs_home(analysis, definition_live);
}

uint allocation_register(uint lane)
{
    static const uint registers[8] = {8u, 9u, 10u, 11u, 3u, 12u, 13u, 14u};
    return registers[min(lane, 7u)];
}

uint non_conflicting_argument_register(uint ordinal)
{
    static const uint registers[4] = {7u, 6u, 2u, 1u};
    return registers[min(ordinal, 3u)];
}

bool adjacent_call_argument_target(
    uint row, uint position, uint last, uint end, uint total,
    uint function_total, out uint physical_register)
{
    physical_register = INVALID;
    if (last != position + 1u || last >= end) return false;
    uint call = semantic_schedule_order[last];
    if (call >= total) return false;
    SemanticLirCore call_core = semantic_lir_core[call];
    uint call_opcode = semantic_lir_op(call_core);
    if (!call_op(call_opcode)) return false;
    uint source_hir = semantic_owner_by_instruction[call];
    if (source_hir >= gParams.function_capacity) return false;

    SemanticLirOperands call_operands = semantic_lir_operands[call];
    uint result_words = call_opcode == SEMANTIC_LIR_OP_CALL &&
        call_operands.a < function_total
            ? semantic_lir_functions[call_operands.a].result_word_count
            : call_opcode == SEMANTIC_LIR_OP_CALL_SYMBOL
                ? call_core.value_word_count : 0u;
    uint abi_ordinal = result_words > 2u ? 1u : 0u;
    uint start = semantic_lir_call_arg_start_by_hir[source_hir];
    uint count = semantic_lir_call_arg_count_by_hir[source_hir];
    uint matches = 0u;
    uint selected_ordinal = INVALID;
    for (uint arg = 0u; arg < min(count, 6u); arg += 1u)
    {
        uint arg_row = start + arg;
        if (arg_row >= gParams.call_arg_capacity) break;
        SemanticLirCallArg value = semantic_lir_call_args[arg_row];
        uint width = (value.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u
            ? 2u : 1u;
        uint argument_type =
            value.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK;
        if (value.call_instruction == call &&
            value.value_instruction == row)
        {
            if (width != 1u ||
                (value.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) != 0u ||
                !x86_scalar_immediate_type(argument_type) || abi_ordinal >= 4u)
                return false;
            matches += 1u;
            selected_ordinal = abi_ordinal;
        }
        abi_ordinal += width;
    }
    if (matches != 1u) return false;
    physical_register = non_conflicting_argument_register(selected_ordinal);
    return true;
}

uint caller_declaration_home(uint function_id, SemanticLirFunction function,
                             uint ordinal, uint declaration)
{
    uint physical = x86_caller_declaration_register(ordinal);
    X86FunctionRegisterAnalysis register_analysis =
        x86_register_analysis_by_function[function_id];
    if (ordinal >= function.param_count ||
        (register_analysis.flags &
         X86_FUNCTION_REGISTER_DIRECT_ABI_HOMES) == 0u)
        return physical;
    uint incoming = x86_abi_argument_register(
        x86_parameter_abi_ordinal(function, ordinal));
    uint last_read = x86_decl_analysis_by_token[declaration].last_read;
    bool before_fixed_clobber = incoming == 2u
        ? register_analysis.first_rdx_clobber == 0u ||
          last_read < register_analysis.first_rdx_clobber
        : incoming == 1u
            ? register_analysis.first_rcx_clobber == 0u ||
              last_read < register_analysis.first_rcx_clobber
            : true;
    return before_fixed_clobber ? incoming : physical;
}

uint parameter_ordinal_for_declaration(SemanticLirFunction function,
                                       uint declaration)
{
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
        if (semantic_lir_params[function.param_start + ordinal].declaration_id ==
            declaration)
            return ordinal;
    return INVALID;
}

bool final_parameter_read_home(uint row, uint position, uint total,
                               uint function_id,
                               SemanticLirFunction function,
                               out uint physical_register,
                               out uint parameter_ordinal)
{
    physical_register = INVALID;
    parameter_ordinal = INVALID;
    SemanticLirCore core = semantic_lir_core[row];
    uint op = semantic_lir_op(core);
    bool unary = op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT;
    if (!unary && op != SEMANTIC_LIR_OP_ADD && op != SEMANTIC_LIR_OP_SUB &&
        op != SEMANTIC_LIR_OP_MUL && op != SEMANTIC_LIR_OP_BIT_AND &&
        op != SEMANTIC_LIR_OP_BIT_OR && op != SEMANTIC_LIR_OP_BIT_XOR &&
        op != SEMANTIC_LIR_OP_SHIFT_LEFT &&
        op != SEMANTIC_LIR_OP_SHIFT_RIGHT)
        return false;

    SemanticLirOperands operands = semantic_lir_operands[row];
    uint immediate;
    if (!unary &&
        (!direct_integer_constant(operands.b, total, immediate) ||
         !x86_integer_immediate_operation(op, core.type_id, immediate)))
        return false;
    uint input = canonical_value(operands.a, total);
    if (input >= total || x86_last_use_by_semantic[input] != position)
        return false;
    SemanticLirCore input_core = semantic_lir_core[input];
    if (semantic_lir_op(input_core) != SEMANTIC_LIR_OP_VALUE_GET)
        return false;
    uint declaration = semantic_lir_operands[input].a;
    if (declaration >= gParams.token_capacity) return false;
    // The live declaration endpoint is recomputed before allocation. A later
    // read or write could observe or overwrite a result that has reused the
    // declaration home.
    if (x86_decl_analysis_by_token[declaration].last_access > position + 1u)
        return false;

    parameter_ordinal =
        parameter_ordinal_for_declaration(function, declaration);
    if (parameter_ordinal >= 6u) return false;
    if ((x86_register_analysis_by_function[function_id].flags &
         X86_FUNCTION_REGISTER_CALL_WITH_LOOP) != 0u)
        return false;
    physical_register = caller_declaration_home(
        function_id, function, parameter_ordinal, declaration);
    if (physical_register == 2u && clobbers_rdx(row, core) ||
        physical_register == 1u && clobbers_rcx(row, core))
    {
        physical_register = INVALID;
        return false;
    }
    return true;
}

bool fixed_parameter_home_survives(uint physical_register, uint position,
                                   uint last, uint total)
{
    if (physical_register != 1u && physical_register != 2u) return true;
    // There are at most six parameter-home candidates in a function, so this
    // bounded walk remains linear in program size while ignoring dead semantic
    // scaffolding between a producer and its final consumer.
    for (uint cursor = position + 1u; cursor < last; cursor += 1u)
    {
        uint row = semantic_schedule_order[cursor];
        if (row >= total || x86_live_by_semantic[row] == 0u) continue;
        SemanticLirCore core = semantic_lir_core[row];
        if (physical_register == 2u ? clobbers_rdx(row, core)
                                    : clobbers_rcx(row, core))
            return false;
    }
    return true;
}

bool declaration_uses_caller_register(uint function_id,
                                      SemanticLirFunction function,
                                      uint physical, uint first_call)
{
    // The inverse of the shared declaration-home map identifies which source
    // declaration reserves each allocator lane without scanning the prefix.
    if (physical < 8u || physical > 11u) return false;
    uint ordinal = x86_caller_declaration_ordinal(physical);
    uint declaration;
    uint type_id;
    if (!declaration_lane_needs_home(
            function, ordinal, declaration, type_id) ||
        !scalar_gpr_type(type_id) || declaration >= gParams.token_capacity)
        return false;
    X86FunctionRegisterAnalysis register_analysis =
        x86_register_analysis_by_function[function_id];
    uint last_read = x86_decl_analysis_by_token[declaration].last_read;
    bool repeated_after_call =
        (register_analysis.flags &
         X86_FUNCTION_REGISTER_CALL_WITH_LOOP) != 0u && last_read != 0u;
    return caller_declaration_home(
               function_id, function, ordinal, declaration) == physical &&
        (first_call == 0u ||
         (last_read < first_call && !repeated_after_call));
}

bool declaration_uses_callee_lane(uint function_id,
                                  SemanticLirFunction function, uint lane,
                                  uint first_call)
{
    uint declaration;
    uint type_id;
    if (lane >= 4u ||
        !declaration_lane_needs_home(
            function, lane, declaration, type_id) ||
        !scalar_gpr_type(type_id) || declaration >= gParams.token_capacity)
        return false;
    uint last_read = x86_decl_analysis_by_token[declaration].last_read;
    bool repeated_after_call =
        (x86_register_analysis_by_function[function_id].flags &
         X86_FUNCTION_REGISTER_CALL_WITH_LOOP) != 0u && last_read != 0u;
    return first_call != 0u &&
        (last_read >= first_call || repeated_after_call);
}

bool removable_local_initializer(uint row, SemanticLirCore core,
                                 SemanticLirOperands operands)
{
    if (semantic_lir_op(core) != SEMANTIC_LIR_OP_VALUE_SET ||
        (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                       SEMANTIC_LIR_FLAG_FIELD)) != 0u ||
        !x86_scalar_immediate_type(core.type_id) ||
        operands.a >= gParams.token_capacity)
        return false;
    return x86_decl_analysis_by_token[operands.a].definition == row;
}

bool observable_root(uint row, SemanticLirCore core)
{
    uint op = semantic_lir_op(core);
    if ((core.flags & (SEMANTIC_LIR_FLAG_UNSUPPORTED |
                       SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE)) != 0u)
        return true;
    // Stores and calls are observable. Control rows define executable CFG
    // structure. Loads and integer division remain roots because their safety
    // checks or hardware traps are observable even when the value is unused.
    return (op == SEMANTIC_LIR_OP_VALUE_SET &&
            !removable_local_initializer(
                row, core, semantic_lir_operands[row])) ||
        op == SEMANTIC_LIR_OP_STORE ||
        call_op(op) ||
        (op >= SEMANTIC_LIR_OP_BLOCK_BEGIN && op <= SEMANTIC_LIR_OP_RETURN) ||
        op == SEMANTIC_LIR_OP_DROP || op == SEMANTIC_LIR_OP_LOAD ||
        op == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
        op == SEMANTIC_LIR_OP_DIV || op == SEMANTIC_LIR_OP_REM;
}

bool preserves_rax(uint op)
{
    // These rows emit no data-manipulation instruction. Every other semantic
    // operation is conservatively a clobber; a final use at the clobber row
    // remains safe because the operand is consumed before its result write.
    return op == SEMANTIC_LIR_OP_NOP ||
        op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_CONTROL_END ||
        op == SEMANTIC_LIR_OP_ELSE ||
        op == SEMANTIC_LIR_OP_BRANCH;
}

bool rax_chain_value(uint row, uint total)
{
    if (row >= total || x86_live_by_semantic[row] == 0u) return false;
    SemanticLirCore core = semantic_lir_core[row];
    uint op = semantic_lir_op(core);
    return scalar_gpr_type(core.type_id) &&
        ((op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_MUL) ||
         op == SEMANTIC_LIR_OP_BIT_AND || op == SEMANTIC_LIR_OP_BIT_OR ||
         op == SEMANTIC_LIR_OP_BIT_XOR ||
         op == SEMANTIC_LIR_OP_LOGICAL_AND ||
         op == SEMANTIC_LIR_OP_LOGICAL_OR ||
         op == SEMANTIC_LIR_OP_NEGATE ||
         op == SEMANTIC_LIR_OP_LOGICAL_NOT);
}

bool rax_chain_binary_consumer(uint op)
{
    return op == SEMANTIC_LIR_OP_ADD || op == SEMANTIC_LIR_OP_SUB ||
        op == SEMANTIC_LIR_OP_MUL || op == SEMANTIC_LIR_OP_BIT_AND ||
        op == SEMANTIC_LIR_OP_BIT_OR || op == SEMANTIC_LIR_OP_BIT_XOR ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR;
}

bool rax_chain_commutative(uint op)
{
    return op != SEMANTIC_LIR_OP_SUB;
}

uint rax_chain_candidate(uint row, uint consumer_position, uint total)
{
    row = canonical_value(row, total);
    if (!rax_chain_value(row, total) ||
        x86_last_use_by_semantic[row] != consumer_position)
        return INVALID;
    uint location = x86_location_by_semantic[row];
    if (location == INVALID ||
        (location & X86_LOCATION_DECLARATION) != 0u)
        return INVALID;
    return row;
}

uint preferred_rax_chain_input(uint consumer, uint consumer_position,
                               uint total)
{
    if (consumer >= total || x86_live_by_semantic[consumer] == 0u ||
        x86_location_by_semantic[consumer] != X86_LOCATION_REGISTER)
        return INVALID;
    SemanticLirCore core = semantic_lir_core[consumer];
    SemanticLirOperands operands = semantic_lir_operands[consumer];
    uint op = semantic_lir_op(core);
    if (op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT)
        return rax_chain_candidate(operands.a, consumer_position, total);
    if (!rax_chain_binary_consumer(op)) return INVALID;

    uint left = rax_chain_candidate(
        operands.a, consumer_position, total);
    uint right = rax_chain_commutative(op)
        ? rax_chain_candidate(operands.b, consumer_position, total) : INVALID;
    if (left == INVALID) return right;
    if (right == INVALID) return left;
    uint rax = X86_LOCATION_REGISTER;
    uint left_cost = x86_move32_between_bytes(
        x86_location_by_semantic[left], rax);
    uint right_cost = x86_move32_between_bytes(
        x86_location_by_semantic[right], rax);
    return right_cost > left_cost ? right : left;
}

bool rax_input_has_register_home(uint row, uint function_id,
                                 SemanticLirFunction function, uint total)
{
    row = canonical_value(row, total);
    if (row >= total) return false;
    uint location = x86_location_by_semantic[row];
    if (x86_location_is_register(location)) return true;
    SemanticLirCore core = semantic_lir_core[row];
    if (semantic_lir_op(core) != SEMANTIC_LIR_OP_VALUE_GET) return false;
    uint declaration = semantic_lir_operands[row].a;
    uint ordinal = parameter_ordinal_for_declaration(function, declaration);
    if (ordinal >= 6u || declaration >= gParams.token_capacity) return false;
    X86FunctionRegisterAnalysis register_analysis =
        x86_register_analysis_by_function[function_id];
    uint last_read = x86_decl_analysis_by_token[declaration].last_read;
    bool repeated_after_call =
        (register_analysis.flags &
         X86_FUNCTION_REGISTER_CALL_WITH_LOOP) != 0u && last_read != 0u;
    bool caller_home = register_analysis.first_call == 0u ||
        (last_read < register_analysis.first_call && !repeated_after_call);
    return caller_home || ordinal < 4u;
}

bool profitable_rax_chain(uint row, uint position, uint function_id,
                          SemanticLirFunction function, uint total)
{
    if (!rax_chain_value(row, total)) return false;
    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    uint op = semantic_lir_op(core);

    // LEA and three-operand immediate IMUL can select RAX without first
    // copying an input there, so they are profitable chain roots.
    if (op == SEMANTIC_LIR_OP_ADD)
    {
        uint left = canonical_value(operands.a, total);
        uint right = canonical_value(operands.b, total);
        if (left < total && right < total &&
            rax_input_has_register_home(
                left, function_id, function, total) &&
            rax_input_has_register_home(
                right, function_id, function, total))
            return true;
    }
    if (op == SEMANTIC_LIR_OP_MUL)
    {
        uint immediate;
        uint shift;
        if (direct_integer_constant(operands.b, total, immediate) &&
            !x86_multiply_immediate_shift(
                X86_LIR_BINARY_MUL_I32, immediate, shift) &&
            !x86_multiply_immediate_negate(
                X86_LIR_BINARY_MUL_I32, immediate))
            return true;
    }

    uint input = INVALID;
    if (op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT)
        input = rax_chain_candidate(operands.a, position, total);
    else if (rax_chain_binary_consumer(op))
    {
        uint left = rax_chain_candidate(operands.a, position, total);
        uint right = rax_chain_commutative(op)
            ? rax_chain_candidate(operands.b, position, total) : INVALID;
        if (left != INVALID &&
            x86_next_rax_clobber_by_semantic[left] != 0u)
            input = left;
        else if (right != INVALID &&
                 x86_next_rax_clobber_by_semantic[right] != 0u)
            input = right;
    }
    return input != INVALID &&
        x86_next_rax_clobber_by_semantic[input] != 0u;
}

bool allocated_row_preserves_rax(uint row)
{
    uint state = x86_live_by_semantic[row];
    if (state == 0u || state == X86_SEMANTIC_COALESCED_ALIAS) return true;
    SemanticLirCore core = semantic_lir_core[row];
    uint op = semantic_lir_op(core);
    if (preserves_rax(op)) return true;
    uint location = x86_location_by_semantic[row];
    if (op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        uint declaration = semantic_lir_operands[row].a;
        // Parameter reads resolve directly to their declaration homes even
        // when the generic allocator tentatively selected RAX for the row.
        // Other reads with an actual RAX result must remain clobber barriers.
        bool parameter_read = declaration < gParams.token_capacity &&
            x86_decl_analysis_by_token[declaration].definition == INVALID;
        return parameter_read ||
            (x86_location_is_register(location) &&
             x86_location_payload(location) != 0u);
    }
    bool non_rax_register = x86_location_is_register(location) &&
        x86_location_payload(location) != 0u;
    return non_rax_register && scalar_gpr_result(core) &&
        (op == SEMANTIC_LIR_OP_CONST_I32 ||
         rax_chain_binary_consumer(op) ||
         op == SEMANTIC_LIR_OP_COMPARE ||
         op == SEMANTIC_LIR_OP_NEGATE ||
         op == SEMANTIC_LIR_OP_LOGICAL_NOT);
}

void coalesce_rax_return_chains(uint start, uint end, uint total,
                                out uint saved_temporary_mask)
{
    saved_temporary_mask = 0u;
    uint next_clobber = INVALID;
    for (uint cursor = end; cursor > start; cursor -= 1u)
    {
        uint position = cursor - 1u;
        uint row = semantic_schedule_order[position];
        if (row >= total) continue;
        uint last = x86_last_use_by_semantic[row];
        if (rax_chain_value(row, total) &&
            x86_next_rax_clobber_by_semantic[row] != 0u && last < end)
        {
            uint consumer = semantic_schedule_order[last];
            if (next_clobber == last &&
                preferred_rax_chain_input(consumer, last, total) == row)
                x86_location_by_semantic[row] = X86_LOCATION_REGISTER;
        }
        uint state = x86_live_by_semantic[row];
        uint location = x86_location_by_semantic[row];
        if (state != 0u && state != X86_SEMANTIC_COALESCED_ALIAS &&
            x86_location_is_register(location))
        {
            uint physical = x86_location_payload(location);
            if (physical == 3u || physical == 12u ||
                physical == 13u || physical == 14u)
                saved_temporary_mask |= 1u << physical;
        }
        if (!allocated_row_preserves_rax(row)) next_clobber = position;
    }
}

bool clobbers_rdx(uint row, SemanticLirCore core)
{
    uint op = semantic_lir_op(core);
    return call_op(op) ||
        ((op == SEMANTIC_LIR_OP_DIV || op == SEMANTIC_LIR_OP_REM) &&
         core.type_id != X86_LIR_TY_FLOAT) ||
        (op == SEMANTIC_LIR_OP_STORE &&
         (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u) ||
        op == SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        op == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
        x86_semantic_type_is_aggregate(core) ||
        x86_live_by_semantic[row] == X86_SEMANTIC_SELECT;
}

bool clobbers_rcx(uint row, SemanticLirCore core)
{
    uint op = semantic_lir_op(core);
    return call_op(op) ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
         (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                        SEMANTIC_LIR_FLAG_FIELD)) != 0u) ||
        op == SEMANTIC_LIR_OP_IF_BEGIN ||
        op == SEMANTIC_LIR_OP_BRANCH_IF ||
        op == SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        op == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
        x86_semantic_type_is_aggregate(core) ||
        x86_live_by_semantic[row] == X86_SEMANTIC_SELECT;
}

bool direct_abi_homes(SemanticLirFunction function)
{
    uint abi_shift = function.result_word_count > 2u ? 1u : 0u;
    if (function.param_count + abi_shift > 6u)
        return false;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        SemanticLirParam param =
            semantic_lir_params[function.param_start + ordinal];
        if (x86_abi_type_width(param.type_id) != 1u) return false;
    }
    return true;
}

uint canonical_value(uint row, uint total)
{
    if (row >= total) return row;
    uint replacement = x86_value_by_semantic[row].replacement;
    return replacement < total ? replacement : row;
}

void mark_dependency(uint value, uint position, uint total, uint function_id)
{
    value = canonical_value(value, total);
    if (value >= total) return;
    uint owner = semantic_owner_by_instruction[value];
    if (owner >= gParams.function_capacity ||
        semantic_function_id_by_hir[owner] != function_id)
        return;
    x86_live_by_semantic[value] = X86_SEMANTIC_LIVE;
    x86_last_use_by_semantic[value] =
        max(x86_last_use_by_semantic[value], position);
}

bool direct_integer_constant(uint row, uint total, out uint value)
{
    value = 0u;
    if (row >= total) return false;
    X86ValueAnalysis analysis = x86_value_by_semantic[row];
    value = analysis.value;
    return analysis.known != 0u;
}

bool instruction_in_function(uint row, uint total, uint function_id)
{
    if (row >= total) return false;
    uint owner = semantic_owner_by_instruction[row];
    return owner < gParams.function_capacity &&
        semantic_function_id_by_hir[owner] == function_id;
}

bool integer_annihilator(uint op, uint value)
{
    return (op == SEMANTIC_LIR_OP_MUL ||
            op == SEMANTIC_LIR_OP_BIT_AND) && value == 0u ||
        op == SEMANTIC_LIR_OP_BIT_OR && value == 0xffffffffu;
}

bool integer_right_identity(uint op, uint value)
{
    return (op == SEMANTIC_LIR_OP_ADD ||
            op == SEMANTIC_LIR_OP_SUB ||
            op == SEMANTIC_LIR_OP_BIT_OR ||
            op == SEMANTIC_LIR_OP_BIT_XOR ||
            op == SEMANTIC_LIR_OP_SHIFT_LEFT ||
            op == SEMANTIC_LIR_OP_SHIFT_RIGHT) && value == 0u ||
        op == SEMANTIC_LIR_OP_MUL && value == 1u ||
        op == SEMANTIC_LIR_OP_BIT_AND && value == 0xffffffffu;
}

bool integer_left_identity(uint op, uint value)
{
    return (op == SEMANTIC_LIR_OP_ADD ||
            op == SEMANTIC_LIR_OP_BIT_OR ||
            op == SEMANTIC_LIR_OP_BIT_XOR) && value == 0u ||
        op == SEMANTIC_LIR_OP_MUL && value == 1u ||
        op == SEMANTIC_LIR_OP_BIT_AND && value == 0xffffffffu;
}

X86ValueAnalysis analyze_integer_value(
    uint row, uint position, uint total, uint function_id)
{
    X86ValueAnalysis result;
    result.value = 0u;
    result.known = 0u;
    result.replacement = row;
    if (row >= total) return result;

    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    uint op = semantic_lir_op(core);
    if (!x86_scalar_immediate_type(core.type_id)) return result;
    if (op == SEMANTIC_LIR_OP_CONST_I32)
    {
        result.value = operands.a;
        result.known = 1u;
        return result;
    }

    uint left;
    uint right;
    if ((op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR)
    {
        bool left_known = direct_integer_constant(operands.a, total, left);
        bool right_known = direct_integer_constant(operands.b, total, right);
        if (left_known && right_known &&
            x86_fold_integer_binary(
                op, core.type_id, operands.c, left, right, result.value))
        {
            result.known = 1u;
            return result;
        }

        // An annihilating constant can reuse the already-materialized
        // constant producer. Producers with side effects or traps remain
        // independently live roots, so redirecting the value does not erase
        // their evaluation.
        uint constant_replacement = INVALID;
        bool right_annihilator =
            right_known && integer_annihilator(op, right);
        bool left_annihilator =
            left_known && integer_annihilator(op, left);
        if (right_annihilator)
            constant_replacement = operands.b;
        else if (left_annihilator)
            constant_replacement = operands.a;
        constant_replacement = canonical_value(constant_replacement, total);
        if (instruction_in_function(
                constant_replacement, total, function_id) &&
            x86_position_by_semantic[constant_replacement] < position &&
            semantic_lir_core[constant_replacement].type_id == core.type_id)
        {
            result.value = right_annihilator ? right : left;
            result.known = 1u;
            result.replacement = constant_replacement;
            return result;
        }

        uint canonical_left = canonical_value(operands.a, total);
        uint canonical_right = canonical_value(operands.b, total);
        if (canonical_left < total && canonical_left == canonical_right)
        {
            if (op == SEMANTIC_LIR_OP_SUB ||
                op == SEMANTIC_LIR_OP_BIT_XOR)
            {
                result.value = 0u;
                result.known = 1u;
                return result;
            }
            if ((op == SEMANTIC_LIR_OP_BIT_AND ||
                 op == SEMANTIC_LIR_OP_BIT_OR) &&
                instruction_in_function(
                    canonical_left, total, function_id) &&
                x86_position_by_semantic[canonical_left] < position &&
                semantic_lir_core[canonical_left].type_id == core.type_id)
            {
                result.replacement = canonical_left;
                return result;
            }
        }

        // Preserve only algebraic identities that are valid for every bit
        // pattern of the scalar integer representation. Logical short-circuit
        // operations are intentionally excluded because their evaluation
        // semantics are not interchangeable with an ordinary value alias.
        uint replacement = INVALID;
        if (right_known && integer_right_identity(op, right))
            replacement = operands.a;
        else if (left_known && integer_left_identity(op, left))
            replacement = operands.b;

        replacement = canonical_value(replacement, total);
        if (instruction_in_function(replacement, total, function_id) &&
            x86_position_by_semantic[replacement] < position &&
            semantic_lir_core[replacement].type_id == core.type_id)
            result.replacement = replacement;
        return result;
    }
    if (op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT)
    {
        if (direct_integer_constant(operands.a, total, left) &&
            x86_fold_integer_unary(op, core.type_id, left, result.value))
            result.known = 1u;
        return result;
    }
    if (op != SEMANTIC_LIR_OP_VALUE_GET ||
        operands.a >= gParams.token_capacity)
        return result;

    // A lexical declaration initializer dominates its later reads. Restrict
    // propagation to VALUE_SET: a single static STORE inside a loop can execute
    // repeatedly and is not a compile-time constant merely because its row is
    // unique.
    uint definition = x86_decl_analysis_by_token[operands.a].definition;
    if (!instruction_in_function(definition, total, function_id) ||
        x86_position_by_semantic[definition] >= position)
        return result;
    SemanticLirCore definition_core = semantic_lir_core[definition];
    SemanticLirOperands definition_operands =
        semantic_lir_operands[definition];
    if (semantic_lir_op(definition_core) != SEMANTIC_LIR_OP_VALUE_SET ||
        (definition_core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                                  SEMANTIC_LIR_FLAG_FIELD)) != 0u ||
        definition_operands.a != operands.a)
        return result;
    uint replacement = canonical_value(definition_operands.b, total);
    if (!instruction_in_function(replacement, total, function_id) ||
        x86_position_by_semantic[replacement] >= position ||
        semantic_lir_core[replacement].type_id != core.type_id)
        return result;
    result.replacement = replacement;
    if (direct_integer_constant(definition_operands.b, total, result.value))
        result.known = 1u;
    return result;
}

bool single_read_boolean_local_comparison(
    uint condition, uint branch_position, uint total, uint function_id,
    out uint comparison, out uint definition)
{
    comparison = INVALID;
    definition = INVALID;
    if (!instruction_in_function(condition, total, function_id)) return false;
    SemanticLirCore condition_core = semantic_lir_core[condition];
    if (semantic_lir_op(condition_core) != SEMANTIC_LIR_OP_VALUE_GET ||
        x86_last_use_by_semantic[condition] != branch_position)
        return false;

    uint declaration = semantic_lir_operands[condition].a;
    if (declaration >= gParams.token_capacity) return false;
    X86DeclarationAnalysis analysis =
        x86_decl_analysis_by_token[declaration];
    if (analysis.read_count != 1u || analysis.definition >= total ||
        analysis.definition == X86_DECLARATION_MULTIPLE_DEFINITIONS)
        return false;

    definition = analysis.definition;
    if (!instruction_in_function(definition, total, function_id)) return false;
    SemanticLirCore definition_core = semantic_lir_core[definition];
    SemanticLirOperands definition_operands =
        semantic_lir_operands[definition];
    uint definition_op = semantic_lir_op(definition_core);
    if ((definition_op != SEMANTIC_LIR_OP_VALUE_SET &&
         definition_op != SEMANTIC_LIR_OP_STORE) ||
        (definition_core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                                  SEMANTIC_LIR_FLAG_FIELD)) != 0u ||
        definition_operands.a != declaration)
        return false;

    uint definition_position = x86_position_by_semantic[definition];
    comparison = definition_operands.b;
    if (definition_position >= branch_position ||
        !instruction_in_function(comparison, total, function_id) ||
        semantic_lir_op(semantic_lir_core[comparison]) !=
            SEMANTIC_LIR_OP_COMPARE ||
        x86_last_use_by_semantic[comparison] != definition_position)
        return false;
    return true;
}

bool replaced_constant_integer_rhs(SemanticLirCore core,
                                   SemanticLirOperands operands,
                                   uint total)
{
    uint immediate;
    if (!direct_integer_constant(operands.b, total, immediate)) return false;
    uint op = semantic_lir_op(core);
    return x86_integer_immediate_operation(op, core.type_id, immediate) ||
        x86_constant_divisor_kind(op, core.type_id, immediate) !=
            X86_CONSTANT_DIVISOR_NONE;
}

bool replaced_constant_integer_lhs(SemanticLirCore core,
                                   SemanticLirOperands operands,
                                   uint total)
{
    uint immediate;
    uint op = semantic_lir_op(core);
    return direct_integer_constant(operands.a, total, immediate) &&
        (x86_integer_immediate_commutative(op) ||
         op == SEMANTIC_LIR_OP_COMPARE) &&
        x86_integer_immediate_operation(op, core.type_id, immediate);
}

void mark_direct_dependencies(uint row, uint position, uint total,
                              uint function_id)
{
    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    uint op = semantic_lir_op(core);
    if (op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        uint ignored;
        if (direct_integer_constant(row, total, ignored) ||
            operands.a >= gParams.token_capacity)
            return;
        uint definition = x86_decl_analysis_by_token[operands.a].definition;
        if (definition < total &&
            x86_position_by_semantic[definition] < position)
            mark_dependency(definition, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        if (op == SEMANTIC_LIR_OP_STORE &&
            (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                           SEMANTIC_LIR_FLAG_FIELD)) != 0u)
        {
            mark_dependency(operands.a, position, total, function_id);
            if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
                mark_dependency(operands.b, position, total, function_id);
            mark_dependency(operands.c, position, total, function_id);
        }
        else mark_dependency(operands.b, position, total, function_id);
    }
    else if ((op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
             op == SEMANTIC_LIR_OP_LOGICAL_AND ||
             op == SEMANTIC_LIR_OP_LOGICAL_OR)
    {
        uint folded_value;
        bool folded = direct_integer_constant(row, total, folded_value);
        bool replaced_lhs = !folded &&
            replaced_constant_integer_lhs(core, operands, total);
        if (replaced_lhs)
            mark_dependency(operands.b, position, total, function_id);
        else if (!folded)
        {
            mark_dependency(operands.a, position, total, function_id);
            if (!replaced_constant_integer_rhs(core, operands, total))
                mark_dependency(operands.b, position, total, function_id);
        }
    }
    else if (op == SEMANTIC_LIR_OP_NEGATE ||
             op == SEMANTIC_LIR_OP_LOGICAL_NOT)
    {
        uint folded;
        if (!direct_integer_constant(row, total, folded))
            mark_dependency(operands.a, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_CONVERT || op == SEMANTIC_LIR_OP_DROP ||
             op == SEMANTIC_LIR_OP_ADDRESS || op == SEMANTIC_LIR_OP_RETURN)
        mark_dependency(operands.a, position, total, function_id);
    else if (op == SEMANTIC_LIR_OP_LOAD)
    {
        mark_dependency(operands.a, position, total, function_id);
        if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
            mark_dependency(operands.b, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_AGGREGATE_COPY)
    {
        mark_dependency(operands.a, position, total, function_id);
        mark_dependency(operands.b, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_IF_BEGIN ||
             op == SEMANTIC_LIR_OP_BRANCH_IF)
        mark_dependency(operands.a, position, total, function_id);

    uint source_hir = semantic_owner_by_instruction[row];
    if (call_op(op) && source_hir < gParams.function_capacity)
    {
        uint start = semantic_lir_call_arg_start_by_hir[source_hir];
        uint count = semantic_lir_call_arg_count_by_hir[source_hir];
        for (uint arg = 0u; arg < count; arg += 1u)
        {
            uint arg_row = start + arg;
            if (arg_row >= gParams.call_arg_capacity) break;
            SemanticLirCallArg value = semantic_lir_call_args[arg_row];
            if (value.call_instruction == row)
            {
                uint argument_type =
                    value.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK;
                uint immediate;
                bool encoded_immediate =
                    (value.value_metadata &
                        (SEMANTIC_LIR_VALUE_AGGREGATE |
                         SEMANTIC_LIR_VALUE_STRING)) == 0u &&
                    x86_scalar_immediate_type(argument_type) &&
                    direct_integer_constant(
                        value.value_instruction, total, immediate);
                if (!encoded_immediate)
                    mark_dependency(value.value_instruction, position, total,
                        function_id);
            }
        }
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        uint element_total = min(gParams.aggregate_capacity,
            semantic_lir_aggregate_element_total[0u]);
        for (uint element = 0u; element < operands.b; element += 1u)
        {
            uint element_row = operands.a + element;
            if (element_row >= element_total) break;
            SemanticLirAggregateElement value =
                semantic_lir_aggregate_elements[element_row];
            if (value.aggregate_instruction == row)
                mark_dependency(value.value_instruction, position, total,
                    function_id);
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint function_total = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    if (function_id >= function_total) return;
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    uint start = x86_function_start[function_id];
    uint end = min(x86_function_end[function_id], total);
    if (start >= end) return;

    if (gParams.reserved0 == 0u)
    {
        // Each function owns one invocation and its semantic schedule is
        // producer-before-consumer, so a single forward walk computes
        // constants through arbitrarily long expression and initialized-local
        // chains.
        for (uint position = start; position < end; position += 1u)
        {
            uint row = semantic_schedule_order[position];
            if (row >= total) continue;
            x86_value_by_semantic[row] = analyze_integer_value(
                row, position, total, function_id);
        }
        // Walking the same schedule in reverse propagates root liveness
        // through the complete value DAG in one pass.
        for (uint cursor = end; cursor > start; cursor -= 1u)
        {
            uint position = cursor - 1u;
            uint row = semantic_schedule_order[position];
            if (row >= total) continue;
            bool live = observable_root(row, semantic_lir_core[row]) ||
                x86_live_by_semantic[row] != 0u;
            x86_live_by_semantic[row] = live ? X86_SEMANTIC_LIVE : 0u;
            if (live)
                mark_direct_dependencies(row, position, total, function_id);
        }
        // A comparison consumed only by a branch does not need a materialized
        // Boolean. Direct expression conditions use schedule adjacency. A
        // named local uses declaration-wide unique-definition and unique-read
        // metadata, so this does not depend on a backward-walk limit.
        for (uint position = start + 1u; position < end; position += 1u)
        {
            uint branch_row = semantic_schedule_order[position];
            uint compare_row = semantic_schedule_order[position - 1u];
            if (branch_row >= total || compare_row >= total) continue;
            uint branch_op = semantic_lir_op(semantic_lir_core[branch_row]);
            if ((branch_op != SEMANTIC_LIR_OP_IF_BEGIN &&
                 branch_op != SEMANTIC_LIR_OP_BRANCH_IF)) continue;
            uint condition = semantic_lir_operands[branch_row].a;
            uint canonical_condition = canonical_value(condition, total);
            uint definition = INVALID;
            bool through_local = false;
            bool direct = canonical_condition == compare_row &&
                semantic_lir_op(semantic_lir_core[compare_row]) ==
                    SEMANTIC_LIR_OP_COMPARE &&
                x86_last_use_by_semantic[compare_row] == position;
            if (!direct)
            {
                if (!single_read_boolean_local_comparison(
                        condition, position, total, function_id,
                        compare_row, definition))
                    continue;
                through_local = true;
            }
            uint left_constant;
            uint right_constant;
            SemanticLirOperands compare_operands =
                semantic_lir_operands[compare_row];
            if (direct_integer_constant(
                    compare_operands.a, total, left_constant) &&
                direct_integer_constant(
                    compare_operands.b, total, right_constant))
                continue;
            x86_live_by_semantic[compare_row] = 0u;
            if (through_local)
            {
                X86SelectInfo info;
                info.condition = compare_row;
                info.true_value = INVALID;
                info.false_value = INVALID;
                info.declaration = semantic_lir_operands[condition].a;
                x86_select_by_semantic[branch_row] = info;
                x86_live_by_semantic[condition] = 0u;
                x86_live_by_semantic[definition] = 0u;
                x86_live_by_semantic[branch_row] =
                    X86_SEMANTIC_COMPARE_ALIAS_BRANCH;
            }
        }
        return;
    }

    // The parallel index records every syntactic read before optimization.
    // Replace that conservative endpoint with the last read that survived
    // value canonicalization and dead-code elimination. This keeps register
    // homes live only for emitted work and gives destructive coalescing an
    // exact declaration boundary without another GPU pass.
    SemanticLirFunction function = semantic_lir_functions[function_id];
    uint remaining_parameter_reads[6];
    uint parameter_snapshot_end[6];
    for (uint ordinal = 0u; ordinal < 6u; ordinal += 1u)
    {
        remaining_parameter_reads[ordinal] = 0u;
        parameter_snapshot_end[ordinal] = 0u;
    }
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        uint declaration =
            semantic_lir_params[function.param_start + ordinal].declaration_id;
        if (declaration >= gParams.token_capacity) continue;
        X86DeclarationAnalysis analysis =
            x86_decl_analysis_by_token[declaration];
        analysis.last_read = 0u;
        analysis.last_access = 0u;
        x86_decl_analysis_by_token[declaration] = analysis;
    }
    for (uint ordinal = 0u; ordinal < function.local_count; ordinal += 1u)
    {
        uint declaration =
            semantic_lir_locals[function.local_start + ordinal].declaration_id;
        if (declaration >= gParams.token_capacity) continue;
        X86DeclarationAnalysis analysis =
            x86_decl_analysis_by_token[declaration];
        analysis.last_read = 0u;
        analysis.last_access = 0u;
        x86_decl_analysis_by_token[declaration] = analysis;
    }
    for (uint position = start; position < end; position += 1u)
    {
        uint row = semantic_schedule_order[position];
        if (row >= total || x86_live_by_semantic[row] == 0u) continue;
        SemanticLirCore core = semantic_lir_core[row];
        uint op = semantic_lir_op(core);
        bool read = op == SEMANTIC_LIR_OP_VALUE_GET;
        bool write = op == SEMANTIC_LIR_OP_VALUE_SET ||
            (op == SEMANTIC_LIR_OP_STORE &&
             (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                            SEMANTIC_LIR_FLAG_FIELD)) == 0u);
        if (!read && !write) continue;
        uint declaration = semantic_lir_operands[row].a;
        if (declaration >= gParams.token_capacity) continue;
        X86DeclarationAnalysis analysis =
            x86_decl_analysis_by_token[declaration];
        if (read) analysis.last_read = position + 1u;
        analysis.last_access = position + 1u;
        x86_decl_analysis_by_token[declaration] = analysis;
        if (read)
        {
            uint parameter_ordinal =
                parameter_ordinal_for_declaration(function, declaration);
            if (parameter_ordinal < 6u)
                remaining_parameter_reads[parameter_ordinal] += 1u;
        }
    }

    // Record the next call strictly after every producer. This makes the
    // caller-saved allocation decision constant-time for arbitrary lifetimes.
    uint next_call = INVALID;
    uint next_rax_clobber = INVALID;
    uint first_rdx_clobber = INVALID;
    uint first_rcx_clobber = INVALID;
    bool has_loop = false;
    for (uint cursor = end; cursor > start; cursor -= 1u)
    {
        uint position = cursor - 1u;
        uint row = semantic_schedule_order[position];
        if (row >= total) continue;
        x86_position_by_semantic[row] = next_call;
        x86_next_rax_clobber_by_semantic[row] = next_rax_clobber;
        SemanticLirCore core = semantic_lir_core[row];
        uint op = semantic_lir_op(core);
        if (op == SEMANTIC_LIR_OP_LOOP_BEGIN) has_loop = true;
        if (call_op(op))
            next_call = position;
        if (x86_live_by_semantic[row] != 0u && !preserves_rax(op))
            next_rax_clobber = position;
        if (x86_live_by_semantic[row] != 0u && clobbers_rdx(row, core))
            first_rdx_clobber = position;
        if (x86_live_by_semantic[row] != 0u && clobbers_rcx(row, core))
            first_rcx_clobber = position;
    }
    X86FunctionRegisterAnalysis register_analysis;
    register_analysis.first_call =
        next_call == INVALID ? 0u : next_call + 1u;
    register_analysis.first_rdx_clobber = first_rdx_clobber == INVALID
        ? 0u : first_rdx_clobber + 1u;
    register_analysis.first_rcx_clobber = first_rcx_clobber == INVALID
        ? 0u : first_rcx_clobber + 1u;
    register_analysis.flags =
        (direct_abi_homes(function)
            ? X86_FUNCTION_REGISTER_DIRECT_ABI_HOMES : 0u) |
        (has_loop && next_call != INVALID
            ? X86_FUNCTION_REGISTER_CALL_WITH_LOOP : 0u);
    x86_register_analysis_by_function[function_id] = register_analysis;

    uint first_call = register_analysis.first_call;
    uint active[ALLOC_REGISTER_COUNT];
    uint declaration_reservation_end[ALLOC_REGISTER_COUNT];
    for (uint lane = 0u; lane < ALLOC_REGISTER_COUNT; lane += 1u)
    {
        uint physical = allocation_register(lane);
        bool declaration_lane = lane < X86_TEMP_REGISTER_COUNT
            ? declaration_uses_caller_register(
                function_id, function, physical, first_call)
            : declaration_uses_callee_lane(function_id, function,
                lane - X86_TEMP_REGISTER_COUNT, first_call);
        active[lane] = declaration_lane ? RESERVED : INVALID;
        declaration_reservation_end[lane] = 0u;
        if (declaration_lane)
        {
            uint ordinal = lane < X86_TEMP_REGISTER_COUNT
                ? x86_caller_declaration_ordinal(physical)
                : lane - X86_TEMP_REGISTER_COUNT;
            uint declaration;
            uint type_id;
            if (declaration_properties(
                    function, ordinal, declaration, type_id) &&
                declaration < gParams.token_capacity)
                declaration_reservation_end[lane] =
                    x86_decl_analysis_by_token[declaration].last_access;
        }
    }
    uint xmm_active[ALLOC_XMM_REGISTER_COUNT];
    for (uint lane = 0u; lane < ALLOC_XMM_REGISTER_COUNT; lane += 1u)
        xmm_active[lane] = INVALID;
    uint temp_saved_mask = 0u;
    uint stack_slots = 0u;
    for (uint position = start; position < end; position += 1u)
    {
        uint row = semantic_schedule_order[position];
        if (row >= total) continue;
        SemanticLirCore core = semantic_lir_core[row];
        uint last = x86_last_use_by_semantic[row];
        uint clobber = x86_position_by_semantic[row];
        uint semantic_state = x86_live_by_semantic[row];
        bool live = semantic_state != 0u;
        bool coalesced_alias =
            semantic_state == X86_SEMANTIC_COALESCED_ALIAS;
        uint assignment_target;
        uint op = semantic_lir_op(core);
        if (live && op == SEMANTIC_LIR_OP_VALUE_GET)
        {
            uint declaration = semantic_lir_operands[row].a;
            uint parameter_ordinal = parameter_ordinal_for_declaration(
                function, declaration);
            if (parameter_ordinal < 6u &&
                remaining_parameter_reads[parameter_ordinal] != 0u)
                remaining_parameter_reads[parameter_ordinal] -= 1u;
            if (parameter_ordinal < 6u)
                parameter_snapshot_end[parameter_ordinal] = max(
                    parameter_snapshot_end[parameter_ordinal],
                    x86_last_use_by_semantic[row]);
        }
        bool in_place_assignment = live && !coalesced_alias &&
            scalar_gpr_result(core) &&
            supports_in_place_assignment(op) &&
            adjacent_assignment_target(row, position, last, end, total,
                assignment_target);
        if (in_place_assignment)
            x86_location_by_semantic[row] = X86_LOCATION_DECLARATION |
                assignment_target;
        uint argument_register;
        bool call_argument_coalesced = live && !coalesced_alias &&
            !in_place_assignment && scalar_gpr_result(core) &&
            produces_scalar_value(op) &&
            adjacent_call_argument_target(row, position, last, end, total,
                function_total, argument_register);
        if (call_argument_coalesced)
            x86_location_by_semantic[row] = X86_LOCATION_REGISTER |
                argument_register;
        uint consumer = last < end ? semantic_schedule_order[last] : INVALID;
        bool returned = consumer < total &&
            semantic_lir_op(semantic_lir_core[consumer]) ==
                SEMANTIC_LIR_OP_RETURN &&
            semantic_lir_operands[consumer].a == row;
        uint parameter_home;
        uint parameter_ordinal;
        bool parameter_read_coalesced = live && !coalesced_alias &&
            !in_place_assignment && !call_argument_coalesced &&
            // ADD/SUB can use a displaced LEA to copy the final parameter
            // read directly into the SysV return register. Destructively
            // reusing the parameter home would add a separate return move.
            !(returned &&
              (op == SEMANTIC_LIR_OP_ADD || op == SEMANTIC_LIR_OP_SUB)) &&
            last > position && scalar_gpr_result(core) &&
            final_parameter_read_home(row, position, total, function_id,
                function, parameter_home, parameter_ordinal);
        if (parameter_read_coalesced)
        {
            bool crosses_call = clobber != INVALID && clobber < last;
            parameter_read_coalesced =
                remaining_parameter_reads[parameter_ordinal] == 0u &&
                parameter_snapshot_end[parameter_ordinal] <= position &&
                !crosses_call && fixed_parameter_home_survives(
                    parameter_home, position, last, total);
        }
        if (parameter_read_coalesced)
        {
            x86_location_by_semantic[row] = X86_LOCATION_REGISTER |
                parameter_home;
            // The final parameter read transfers ownership of its physical
            // home from the declaration to this result interval. R8-R11 are
            // also generic allocation lanes, so keep the row active until
            // its actual last use; otherwise a later producer can overwrite
            // a still-live destructively coalesced value.
            for (uint lane = 0u; lane < ALLOC_REGISTER_COUNT; lane += 1u)
            {
                if (allocation_register(lane) != parameter_home) continue;
                active[lane] = row;
                declaration_reservation_end[lane] = 0u;
                break;
            }
        }
        bool allocatable = live && !coalesced_alias &&
            !in_place_assignment && !call_argument_coalesced &&
            !parameter_read_coalesced &&
            last > position &&
            scalar_gpr_result(core) &&
            produces_scalar_value(op);
        if (allocatable)
        {
            uint next_rax = x86_next_rax_clobber_by_semantic[row];
            bool fixed_rax = (call_op(op) || returned) &&
                (next_rax == INVALID || next_rax >= last);
            if (fixed_rax)
                x86_location_by_semantic[row] = X86_LOCATION_REGISTER;
            else
            {
                // A value whose final use supplies an argument to the call is
                // consumed before the call executes, so it does not cross the
                // caller-saved clobber boundary. Only uses strictly after the
                // call require a callee-saved register or spill slot.
                bool crosses_call = clobber != INVALID && clobber < last;
                uint first_lane = crosses_call ? X86_TEMP_REGISTER_COUNT : 0u;
                for (uint lane = first_lane; lane < ALLOC_REGISTER_COUNT; lane += 1u)
                {
                    uint occupant = active[lane];
                    bool available = occupant == INVALID ||
                        (occupant == RESERVED
                            ? declaration_reservation_end[lane] <= position + 1u
                            : x86_last_use_by_semantic[occupant] <= position);
                    if (!available) continue;
                    active[lane] = row;
                    uint physical = allocation_register(lane);
                    x86_location_by_semantic[row] = X86_LOCATION_REGISTER |
                        physical;
                    if (lane >= X86_TEMP_REGISTER_COUNT)
                        temp_saved_mask |= 1u << physical;
                    break;
                }
            }
        }

        bool xmm_allocatable = live && !coalesced_alias &&
            x86_location_by_semantic[row] == INVALID &&
            last > position && core.type_id == X86_LIR_TY_FLOAT &&
            produces_f32_value(op);
        if (xmm_allocatable)
        {
            bool crosses_call = clobber != INVALID && clobber < last;
            if (!crosses_call)
            {
                for (uint lane = 0u; lane < ALLOC_XMM_REGISTER_COUNT;
                     lane += 1u)
                {
                    uint occupant = xmm_active[lane];
                    if (occupant != INVALID &&
                        x86_last_use_by_semantic[occupant] > position)
                        continue;
                    xmm_active[lane] = row;
                    x86_location_by_semantic[row] = x86_xmm_location(lane);
                    break;
                }
            }
        }

        // Stack locations are compact function-local indices. Only live
        // values that were not assigned a register receive storage;
        // multiword values retain one contiguous range.
        if (live && !coalesced_alias &&
            x86_location_by_semantic[row] == INVALID)
        {
            uint words = stack_word_count(row, total, function_total);
            if (words != 0u)
            {
                x86_location_by_semantic[row] = stack_slots;
                stack_slots += words;
            }
        }
        // The next-RAX-clobber interval has served its allocation purpose for
        // this producer. Reuse the same phase-local word for a forward dynamic
        // program that proves whether a backward RAX chain has a no-copy root.
        x86_next_rax_clobber_by_semantic[row] =
            profitable_rax_chain(
                row, position, function_id, function, total) ? 1u : 0u;
    }
    // Allocation has established every physical location, so this reverse
    // walk can safely propagate the SysV return register through destructive
    // integer chains. A row is recolored only when its sole remaining use is
    // the next operation that writes RAX; unrelated operations retain their
    // actual allocated locations when deciding whether the chain survives.
    // Recoloring may remove the final temporary from a callee-saved register.
    // Declaration homes are ORed in by decl_slots_scatter; the reverse walk
    // rebuilds only the temporary portion without another schedule traversal.
    coalesce_rax_return_chains(start, end, total, temp_saved_mask);
    x86_stack_slot_count_by_function[function_id] = stack_slots;
    x86_frame_slot_count_by_function[function_id] = stack_slots;
    x86_saved_gpr_mask_by_function[function_id] = temp_saved_mask;
}
