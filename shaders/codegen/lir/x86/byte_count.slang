import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.location_common;
import codegen.lir.x86.safety;
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
StructuredBuffer<uint> x86_decl_location_by_token;
StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
RWStructuredBuffer<uint> target_byte_length;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint declaration_location(uint token)
{
    uint location = token < gParams.token_capacity
        ? x86_decl_location_by_token[token] : X86_LOCATION_INVALID;
    return location == X86_LOCATION_INVALID ? 0u : location;
}

bool frameless_function(TargetLirFunction function,
                        SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_FRAMELESS) != 0u &&
        semantic_function.result_word_count <= 2u;
}

bool stackless_caller(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_STACKLESS_CALLER) != 0u &&
        semantic_function.result_word_count <= 2u;
}

uint base_frame_slots(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK) +
        (semantic_function.result_word_count > 2u ? 1u : 0u);
}

uint hidden_sret_slot(TargetLirFunction function)
{
    return function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
}

uint param_store_bytes(TargetLirFunction target_function,
                       SemanticLirFunction function, uint hidden_sret)
{
    uint bytes = hidden_sret != 0u
        ? x86_stack64_operand_bytes(hidden_sret_slot(target_function)) : 0u;
    uint abi_ordinal = hidden_sret;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        uint width = x86_abi_type_width(param.type_id);
        if (abi_ordinal + width > 6u) break;
        uint destination = declaration_location(param.declaration_id);
        bytes += x86_move64_from_fixed_bytes(x86_abi_argument_register(abi_ordinal), destination);
        if (width == 2u)
            bytes += x86_move64_from_fixed_bytes(x86_abi_argument_register(abi_ordinal + 1u),
                destination + 1u);
        abi_ordinal += width;
    }
    return bytes;
}

uint function_abi_param_count(SemanticLirFunction function)
{
    uint count = 0u;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
        count += x86_abi_type_width(
            semantic_lir_params[function.param_start + ordinal].type_id);
    return count;
}

bool f32_binary_commutative(uint operation)
{
    return operation == X86_LIR_BINARY_ADD_F32 ||
        operation == X86_LIR_BINARY_MUL_F32;
}

uint f32_binary_instruction_bytes(uint destination, uint right)
{
    if (x86_location_is_xmm(right))
        return 4u + (destination >= 8u ||
            x86_location_xmm(right) >= 8u ? 1u : 0u);
    if (x86_location_is_register(right))
        return x86_move_f32_to_xmm_bytes(right, 14u) +
            5u;
    return x86_stack_xmm32_operand_bytes(x86_location_payload(right)) +
        (destination >= 8u ? 1u : 0u);
}

uint f32_binary_bytes(uint operation, uint left, uint right, uint result)
{
    uint destination = x86_location_is_xmm(result)
        ? x86_location_xmm(result) : 15u;
    bool destination_is_right = x86_location_is_xmm(right) &&
        x86_location_xmm(right) == destination;
    bool destination_is_left = x86_location_is_xmm(left) &&
        x86_location_xmm(left) == destination;
    if (destination_is_right && !destination_is_left &&
        f32_binary_commutative(operation))
    {
        uint swap = left;
        left = right;
        right = swap;
        destination_is_right = false;
    }
    uint compute = destination_is_right && !destination_is_left
        ? 15u : destination;
    return x86_move_f32_to_xmm_bytes(left, compute) +
        f32_binary_instruction_bytes(compute, right) +
        x86_move_f32_from_xmm_bytes(compute, result);
}

uint f32_compare_instruction_bytes(uint left, uint right)
{
    uint left_xmm = x86_location_is_xmm(left)
        ? x86_location_xmm(left) : 15u;
    uint bytes = x86_move_f32_to_xmm_bytes(left, left_xmm);
    if (x86_location_is_xmm(right))
        bytes += 3u + (left_xmm >= 8u ||
            x86_location_xmm(right) >= 8u ? 1u : 0u);
    else if (x86_location_is_register(right))
        bytes += x86_move_f32_to_xmm_bytes(right, 14u) +
            4u;
    else
        bytes += 3u + x86_stack_displacement_bytes(
            x86_location_payload(right)) + (left_xmm >= 8u ? 1u : 0u);
    return bytes;
}

uint f32_compare_bytes(uint left, uint right, uint result)
{
    return f32_compare_instruction_bytes(left, right) +
        x86_boolean_result_bytes(result);
}

uint instruction_bytes(X86LirCore core, X86LirOperands operands,
                       X86LirLocations locations,
                       TargetLirFunction function,
                       SemanticLirFunction semantic_function,
                       uint saved_mask)
{
    bool frameless = frameless_function(function, semantic_function);
    uint restore_bytes = x86_saved_gpr_frame_bytes(saved_mask,
        base_frame_slots(function, semantic_function));
    if (core.op == X86_LIR_OP_IMM_I32)
        return (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
            ? x86_imm_f32_to_location_bytes(operands.a, locations.result)
            : x86_imm32_to_location_bytes(operands.a, locations.result);
    if (core.op == X86_LIR_OP_ALIAS)
    {
        uint component = (operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u
            ? operands.c : 0u;
        uint source = declaration_location(operands.a) + component;
        return (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
            ? x86_move_f32_between_bytes(source, locations.result)
            : x86_alias_uses_64_bits(operands.metadata)
            ? x86_move64_between_bytes(source, locations.result)
            : x86_move32_between_bytes(source, locations.result);
    }
    if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        uint destination = declaration_location(operands.a);
        if ((operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u)
            return x86_move64_between_bytes(locations.b, destination) +
                x86_move32_between_bytes(locations.c, destination + 1u);
        bool wide = (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u ||
            (operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER;
        return (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u
            ? x86_stack64_operand_bytes(
                x86_location_payload(locations.result) + 1u) +
                x86_move64_from_fixed_bytes(0u, destination)
            : (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
            ? x86_move_f32_between_bytes(locations.b, destination)
            : wide ? x86_move64_between_bytes(locations.b, destination)
            : x86_move32_between_bytes(locations.b, destination);
    }
    if (core.op == X86_LIR_OP_BINARY)
    {
        if (operands.a >= X86_LIR_BINARY_ADD_F32 && operands.a <= X86_LIR_BINARY_DIV_F32)
            return f32_binary_bytes(operands.a, locations.b, locations.c,
                locations.result);
        if (x86_const_pow2_binary(operands.a))
            return x86_const_pow2_binary_bytes(operands.a, operands.c,
                operands.metadata & 0xffu, locations.b, locations.result);
        if (x86_const_signed_binary(operands.a))
            return x86_const_signed_binary_bytes(operands.a, operands.c,
                locations.b, locations.result);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            return x86_binary_immediate_bytes(operands.a, operands.c,
                locations.b, locations.result);
        if ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER)
            return x86_move64_to_fixed_bytes(locations.b, 0u) +
                x86_move32_to_fixed_bytes(locations.c, 1u) + 3u +
                x86_move64_from_fixed_bytes(0u, locations.result);
        if (operands.a == X86_LIR_BINARY_ADD_I32 &&
            x86_lea_add32_preferred(locations.b, locations.c,
                locations.result))
            return x86_lea_add32_bytes(locations.b, locations.c,
                locations.result);
        if (x86_location_is_register(locations.result) &&
            x86_direct_binary32_supported(operands.a) &&
            (locations.result != locations.c ||
             locations.result == locations.b ||
             x86_binary32_commutative(operands.a)))
        {
            bool swapped = locations.result == locations.c &&
                locations.result != locations.b;
            uint right = swapped ? locations.b : locations.c;
            uint setup = swapped ? 0u : x86_move32_between_bytes(
                locations.b, locations.result);
            return setup + x86_direct_binary32_opcode_bytes(operands.a,
                right, locations.result);
        }
        return x86_move32_to_fixed_bytes(locations.b, 0u) +
            x86_move32_to_fixed_bytes(locations.c, 1u) +
            x86_binary_opcode_bytes(operands.a, operands.metadata & 0xffu) +
            x86_move32_from_fixed_bytes(0u, locations.result);
    }
    if (core.op == X86_LIR_OP_COMPARE)
        return (operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
            ? x86_compare_immediate_bytes(
                operands.c, locations.b, locations.result) :
            (operands.metadata & 0xffu) == 5u ?
            f32_compare_bytes(locations.b, locations.c, locations.result) :
            (operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER ?
            x86_move64_to_fixed_bytes(locations.b, 0u) +
            ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) != 0u
                ? x86_move32_to_fixed_bytes(locations.c, 1u)
                : x86_move64_to_fixed_bytes(locations.c, 1u)) + 3u +
            x86_boolean_result_bytes(locations.result) :
            x86_compare32_instruction_bytes(locations.b, locations.c) +
            x86_boolean_result_bytes(locations.result);
    if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            return x86_compare_immediate_instruction_bytes(
                operands.b, locations.a) + 6u;
        if ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT)
            return f32_compare_instruction_bytes(
                locations.a, locations.b) + 6u;
        bool pointer = (operands.metadata & 0xffu) ==
            SEMANTIC_LIR_TY_POINTER;
        return (pointer
            ? x86_move64_to_fixed_bytes(locations.a, 0u) +
                ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) != 0u
                    ? x86_move32_to_fixed_bytes(locations.b, 1u)
                    : x86_move64_to_fixed_bytes(locations.b, 1u)) + 3u
            : x86_compare32_instruction_bytes(locations.a, locations.b)) + 6u;
    }
    if (core.op == X86_LIR_OP_SELECT_STORE)
    {
        uint destination = declaration_location(core.result_or_target);
        uint compare_bytes =
            (operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
                ? x86_compare_immediate_instruction_bytes(
                    operands.b, locations.a)
                : x86_compare32_instruction_bytes(
                    locations.a, locations.b);
        if (x86_location_is_register(destination))
            return x86_move32_between_bytes(locations.result, destination) +
                compare_bytes + x86_move32_to_fixed_bytes(locations.c, 0u) +
                (x86_location_payload(destination) >= 8u ? 1u : 0u) + 3u;
        return x86_move32_to_fixed_bytes(locations.result, 2u) +
            compare_bytes + x86_move32_to_fixed_bytes(locations.c, 0u) + 3u +
            x86_move32_from_fixed_bytes(2u, destination);
    }
    if (core.op == X86_LIR_OP_UNARY)
    {
        uint direct = x86_direct_unary32_bytes(
            operands.a, locations.b, locations.result);
        if (direct != 0u) return direct;
        return operands.a == X86_LIR_UNARY_NEG_I32
             ? x86_move32_to_fixed_bytes(locations.b, 0u) + 2u +
               x86_move32_from_fixed_bytes(0u, locations.result)
             : operands.a == X86_LIR_UNARY_NOT_BOOL
             ? x86_move32_to_fixed_bytes(locations.b, 0u) + 8u +
               x86_move32_from_fixed_bytes(0u, locations.result)
             : operands.a == X86_LIR_UNARY_NEG_F32
             ? x86_move_f32_to_gpr_bytes(locations.b, 0u) + 5u +
               x86_move_f32_from_gpr_bytes(0u, locations.result)
             : 0u;
    }
    if (core.op == X86_LIR_OP_RETURN)
        return operands.c != 0u
            ? (operands.c > 2u
                ? x86_stack64_operand_bytes(hidden_sret_slot(function))
                : 0u) + restore_bytes +
                (frameless ? 1u : 2u)
            : (operands.a == INVALID ? 2u :
               (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
                   ? x86_move_f32_to_gpr_bytes(locations.a, 0u)
                   : (operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER
                   ? x86_move64_to_fixed_bytes(locations.a, 0u)
                   : x86_move32_to_fixed_bytes(locations.a, 0u)) +
              restore_bytes + (frameless ? 1u : 2u);
    if (core.op == X86_LIR_OP_RETURN_VOID)
        return 2u + restore_bytes + (frameless ? 1u : 2u);
    if (core.op == X86_LIR_OP_CALL_ARG)
    {
        if (operands.b >= 6u) return 0u;
        uint destination = X86_LOCATION_REGISTER | x86_abi_argument_register(operands.b);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            return x86_imm32_to_location_bytes(operands.a, destination);
        bool wide = (operands.metadata &
            (X86_LIR_METADATA_AGGREGATE | X86_LIR_METADATA_WIDE)) != 0u;
        return (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
                    ? x86_move_f32_to_gpr_bytes(
                        locations.a, x86_location_payload(destination))
                    : wide ? x86_move64_between_bytes(locations.a, destination)
                    : x86_move32_between_bytes(locations.a, destination);
    }
    if (core.op == X86_LIR_OP_CALL || core.op == X86_LIR_OP_CALL_SYMBOL)
    {
        uint result_words = core.op == X86_LIR_OP_CALL
            ? operands.c : core.local_ordinal;
        if ((operands.metadata & X86_LIR_METADATA_AGGREGATE) == 0u)
            return 5u + ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
                ? x86_move_f32_from_gpr_bytes(0u, locations.result)
                : (operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER
                ? x86_move64_from_fixed_bytes(0u, locations.result)
                : x86_move32_from_fixed_bytes(0u, locations.result));
        if (result_words == 0u) return 0u;
        uint storage_slot = x86_location_payload(locations.result) + 1u;
        uint result_store = x86_move64_from_fixed_bytes(0u, locations.result);
        if (result_words > 2u)
            return x86_stack64_operand_bytes(storage_slot) + 5u + result_store;
        uint bytes = 5u + x86_stack64_operand_bytes(storage_slot);
        if (result_words > 1u)
            bytes += x86_stack64_operand_bytes(storage_slot + 1u);
        return bytes + x86_stack64_operand_bytes(storage_slot) + result_store;
    }
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a == HOST_SERVICE_I32_TO_F32)
        return 4u + x86_move_f32_from_xmm_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_CALL_HOST && x86_runtime_service_supported(operands.a))
        return x86_runtime_service_has_result(operands.a)
            ? 5u + ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_POINTER
                ? x86_move64_from_fixed_bytes(0u, locations.result)
                : x86_move32_from_fixed_bytes(0u, locations.result)) : 5u;
    if (core.op == X86_LIR_OP_PRINT_I32 && operands.a == 1u) return 5u;
    if (core.op == X86_LIR_OP_INTRINSIC_IDENTITY)
        return x86_move64_from_fixed_bytes(7u, locations.result);
    if (core.op == X86_LIR_OP_AGGREGATE_ADDR)
        return x86_stack64_operand_bytes(
                x86_location_payload(locations.result) + 1u) +
            x86_move64_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_AGGREGATE_INIT)
        return ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
                ? 5u
                : (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
                ? x86_move_f32_to_gpr_bytes(locations.a, 0u)
                : x86_move64_to_fixed_bytes(locations.a, 0u)) +
            ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u ? 7u : 0u) +
            x86_move64_from_fixed_bytes(0u, locations.c);
    if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        bool aggregate =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool f32 = !aggregate &&
            (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT;
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            x86_move32_to_fixed_bytes(locations.b, 1u) +
            (aggregate ? 14u : f32 ? 6u : 7u) +
            (f32 ? x86_move_f32_from_gpr_bytes(0u, locations.result)
                 : x86_move64_from_fixed_bytes(0u, locations.result));
    }
    if (core.op == X86_LIR_OP_FIELD_LOAD)
    {
        bool aggregate =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool f32 = !aggregate &&
            (operands.metadata & 0xffu) == X86_LIR_TY_FLOAT;
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            (f32 ? 6u : 7u) +
            (f32 ? x86_move_f32_from_gpr_bytes(0u, locations.result)
                 : x86_move64_from_fixed_bytes(0u, locations.result));
    }
    if (core.op == X86_LIR_OP_INDEX_STORE)
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            x86_move32_to_fixed_bytes(locations.b, 1u) +
            ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
                ? x86_move_f32_to_gpr_bytes(locations.c, 2u)
                : x86_move32_to_fixed_bytes(locations.c, 2u)) + 7u;
    if (core.op == X86_LIR_OP_FIELD_STORE)
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            ((operands.metadata & 0xffu) == X86_LIR_TY_FLOAT
                ? x86_move_f32_to_gpr_bytes(locations.c, 1u)
                : x86_move32_to_fixed_bytes(locations.c, 1u)) + 7u;
    if (core.op == X86_LIR_OP_AGGREGATE_RESULT_SLOT) return 0u;
    if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
        return operands.c > 2u
            ? x86_move64_to_fixed_bytes(locations.a, 0u) +
                x86_stack64_operand_bytes(hidden_sret_slot(function)) +
                (operands.b == 0u ? 6u : 14u)
            : x86_move64_to_fixed_bytes(locations.a,
                operands.b == 0u ? 0u : 1u) +
                (operands.b == 0u ? 3u : 7u);
    if (core.op == X86_LIR_OP_AGGREGATE_COPY_WORD)
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            (operands.b == 0u ? 3u : 7u) +
            x86_move64_from_fixed_bytes(1u, locations.result);
    if (core.op == X86_LIR_OP_STRING_ADDR)
        return 10u + x86_move64_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_STRING_LEN)
        return 5u + x86_move32_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_BRANCH) return operands.a == INVALID ? 5u :
        x86_test32_instruction_bytes(locations.a) + 6u;
    if (core.op == X86_LIR_OP_LABEL) return 0u;
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= gParams.target_capacity) return;
    target_byte_length[row] = 0u;
    if (row >= total) return;
    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    X86LirLocations locations = target_lir_locations[page_row];
    uint function_id = semantic_function_id_by_hir[core.source_hir];
    uint function_count = min(gParams.function_capacity,
        min(target_function_count[0u], semantic_lir_function_total[0u]));
    uint function_index = function_id < gParams.function_capacity
        ? target_function_index_by_semantic[function_id] : INVALID;
    if (function_index >= function_count)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
        return;
    }
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    uint saved_mask = x86_saved_gpr_mask_by_function[function_id];
    bool frameless = frameless_function(function, semantic_function);
    bool stackless = stackless_caller(function, semantic_function);
    uint bytes = instruction_bytes(core, operands, locations, function,
        semantic_function, saved_mask) +
        x86_safety_guard_bytes(core, operands, locations);
    bool zero_binary_identity = core.op == X86_LIR_OP_BINARY &&
        (operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u &&
        x86_binary_immediate_identity(operands.a, operands.c) &&
        locations.b == locations.result;
    bool supported_zero = core.op == X86_LIR_OP_LABEL ||
        core.op == X86_LIR_OP_AGGREGATE_RESULT_SLOT ||
        core.op == X86_LIR_OP_ALIAS ||
        core.op == X86_LIR_OP_STORE_LOCAL ||
        core.op == X86_LIR_OP_CALL_ARG ||
        core.op == X86_LIR_OP_INTRINSIC_IDENTITY || zero_binary_identity;
    if (bytes == 0u && !supported_zero)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_ARG &&
        (operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
        operands.a >= total)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if ((core.op == X86_LIR_OP_AGGREGATE_INIT &&
         (operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
         operands.a >= total) ||
        (core.op == X86_LIR_OP_INDEX_LOAD &&
         (operands.a >= total || operands.b >= total)) ||
        (core.op == X86_LIR_OP_FIELD_LOAD && operands.a >= total))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if ((core.op == X86_LIR_OP_INDEX_STORE &&
         (operands.a >= total || operands.b >= total || operands.c >= total)) ||
        (core.op == X86_LIR_OP_FIELD_STORE &&
         (operands.a >= total || operands.c >= total)))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE &&
        (operands.a >= total || core.result_or_target >= total ||
         ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
          operands.b >= total)))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_SELECT_STORE &&
        (declaration_location(core.result_or_target) == X86_LOCATION_INVALID ||
         locations.result == X86_LOCATION_INVALID || operands.a >= total ||
         operands.c >= total ||
         ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
          operands.b >= total)))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    uint callee_index = operands.a < gParams.function_capacity
        ? target_function_index_by_semantic[operands.a] : INVALID;
    if (core.op == X86_LIR_OP_CALL && callee_index >= function_count)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_SYMBOL &&
        (operands.a == INVALID || operands.b == INVALID || operands.c == INVALID))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a != HOST_SERVICE_I32_TO_F32 &&
        !x86_runtime_service_supported(operands.a))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    uint hidden_sret = semantic_function.result_word_count > 2u ? 1u : 0u;
    if (function_abi_param_count(semantic_function) + hidden_sret > 6u)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (row == function.instruction_start)
    {
        uint first_saved_slot = base_frame_slots(function, semantic_function);
        uint frame_slots = first_saved_slot + x86_saved_gpr_count(saved_mask);
        uint saved_bytes = x86_saved_gpr_frame_bytes(
            saved_mask, first_saved_slot);
        bytes += (frameless ? 0u : stackless ? 1u :
            4u + (frame_slots == 0u ? 0u : 7u) +
            saved_bytes) +
            param_store_bytes(function, semantic_function, hidden_sret);
    }
    bool final_explicit_return = core.op == X86_LIR_OP_RETURN ||
        core.op == X86_LIR_OP_RETURN_VOID;
    if (row + 1u == function.instruction_start + function.instruction_count &&
        !final_explicit_return)
        bytes += (frameless ? 3u : stackless ? 4u : 4u +
            x86_saved_gpr_frame_bytes(saved_mask,
                base_frame_slots(function, semantic_function)));
    target_byte_length[row] = bytes;
}
