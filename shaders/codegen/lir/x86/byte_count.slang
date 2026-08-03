import codegen.lowering_ir;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.location_common;
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

uint argument_register(uint ordinal)
{
    static const uint registers[6] = {7u, 6u, 2u, 1u, 8u, 9u};
    return registers[min(ordinal, 5u)];
}

uint declaration_location(uint token)
{
    uint location = token < gParams.token_capacity
        ? x86_decl_location_by_token[token] : X86_LOCATION_INVALID;
    return location == X86_LOCATION_INVALID ? 0u : location;
}

uint param_store_bytes(SemanticLirFunction function, uint hidden_sret)
{
    uint bytes = hidden_sret != 0u ? 7u : 0u;
    for (uint ordinal = 0u;
         ordinal < min(function.param_count, 6u - hidden_sret); ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        bytes += x86_move64_from_fixed_bytes(argument_register(ordinal + hidden_sret),
            declaration_location(param.declaration_id));
    }
    return bytes;
}

uint instruction_bytes(X86LirCore core, X86LirOperands operands,
                       X86LirLocations locations, uint saved_mask)
{
    uint restore_bytes = x86_saved_gpr_count(saved_mask) * 7u;
    if (core.op == X86_LIR_OP_IMM_I32)
        return 5u + x86_move32_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_ALIAS)
    {
        uint source = declaration_location(operands.a);
        return x86_move64_to_fixed_bytes(source, 0u) +
            x86_move64_from_fixed_bytes(0u, locations.result);
    }
    if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        uint destination = declaration_location(operands.a);
        return (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u
            ? x86_move64_to_fixed_bytes(locations.b, 0u) +
              3u + 5u + x86_move64_from_fixed_bytes(0u, destination)
            : x86_move32_to_fixed_bytes(locations.b, 0u) +
              x86_move32_from_fixed_bytes(0u, destination);
    }
    if (core.op == X86_LIR_OP_BINARY)
    {
        if (operands.a >= X86_LIR_BINARY_ADD_F32 && operands.a <= X86_LIR_BINARY_DIV_F32)
            return 28u;
        return x86_move32_to_fixed_bytes(locations.b, 0u) +
            x86_move32_to_fixed_bytes(locations.c, 1u) +
            x86_binary_opcode_bytes(operands.a) +
            x86_move32_from_fixed_bytes(0u, locations.result);
    }
    if (core.op == X86_LIR_OP_COMPARE)
        return (operands.metadata & 0xffu) == 5u ? 31u :
            x86_move32_to_fixed_bytes(locations.b, 0u) +
            x86_move32_to_fixed_bytes(locations.c, 1u) + 8u +
            x86_move32_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_UNARY)
        return operands.a == X86_LIR_UNARY_NEG_I32
             ? x86_move32_to_fixed_bytes(locations.b, 0u) + 2u +
               x86_move32_from_fixed_bytes(0u, locations.result)
             : operands.a == X86_LIR_UNARY_NOT_BOOL
             ? x86_move32_to_fixed_bytes(locations.b, 0u) + 9u +
               x86_move32_from_fixed_bytes(0u, locations.result)
             : operands.a == X86_LIR_UNARY_NEG_F32 ? 17u : 0u;
    if (core.op == X86_LIR_OP_RETURN)
        return operands.c != 0u
            ? x86_move64_to_fixed_bytes(locations.a, 0u) + restore_bytes + 2u
            : (operands.a == INVALID ? 2u :
               x86_move32_to_fixed_bytes(locations.a, 0u)) +
              restore_bytes + 2u;
    if (core.op == X86_LIR_OP_RETURN_VOID) return 4u + restore_bytes;
    if (core.op == X86_LIR_OP_CALL_ARG)
    {
        if (operands.b >= 6u) return 0u;
        bool wide = (operands.metadata &
            (X86_LIR_METADATA_AGGREGATE | X86_LIR_METADATA_WIDE)) != 0u;
        return (wide ? x86_move64_to_fixed_bytes(locations.a, 0u)
                     : x86_move32_to_fixed_bytes(locations.a, 0u)) +
            (wide ? 3u : operands.b < 4u ? 2u : 3u);
    }
    if (core.op == X86_LIR_OP_CALL)
        return (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u
            ? 5u + x86_move64_from_fixed_bytes(0u, locations.result)
            : 5u + x86_move32_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_CALL_SYMBOL)
        return (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u
            ? 5u + x86_move64_from_fixed_bytes(0u, locations.result)
            : 5u + x86_move32_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a == HOST_SERVICE_I32_TO_F32) return 12u;
    if (core.op == X86_LIR_OP_CALL_HOST && x86_runtime_service_supported(operands.a))
        return x86_runtime_service_has_result(operands.a)
            ? 5u + x86_move32_from_fixed_bytes(0u, locations.result) : 5u;
    if (core.op == X86_LIR_OP_PRINT_I32 && operands.a == 1u) return 5u;
    if (core.op == X86_LIR_OP_ARRAY_ADDR)
        return 20u + x86_move64_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_ARRAY_INIT)
        return x86_move64_to_fixed_bytes(locations.c, 0u) +
            x86_move64_to_fixed_bytes(locations.a, 1u) + 7u;
    if (core.op == X86_LIR_OP_INDEX_LOAD)
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            x86_move32_to_fixed_bytes(locations.b, 1u) + 4u +
            x86_move64_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_FIELD_LOAD)
        return x86_move64_to_fixed_bytes(locations.a, 0u) + 7u +
            x86_move64_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_INDEX_STORE)
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            x86_move32_to_fixed_bytes(locations.b, 1u) +
            x86_move32_to_fixed_bytes(locations.c, 2u) + 4u;
    if (core.op == X86_LIR_OP_FIELD_STORE)
        return x86_move64_to_fixed_bytes(locations.a, 0u) +
            x86_move32_to_fixed_bytes(locations.c, 1u) + 7u;
    if (core.op == X86_LIR_OP_AGGREGATE_RESULT_SLOT) return 0u;
    if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD) return 0u;
    if (core.op == X86_LIR_OP_STRING_ADDR) return 17u;
    if (core.op == X86_LIR_OP_STRING_LEN) return 11u;
    if (core.op == X86_LIR_OP_BRANCH) return operands.a == INVALID ? 5u :
        x86_move32_to_fixed_bytes(locations.a, 0u) + 8u;
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
    if (core.source_hir == 11u)
    {
        // TEMP diagnostic: prove which target row owns the first unsupported
        // source HIR and expose its opcode in the status packet.
        InterlockedMin(lowering_status[0u].available_capacity, 7000u + core.op);
        InterlockedMin(lowering_status[0u].required_capacity,
            min(operands.a, 999u));
    }
    uint function_id = semantic_function_id_by_hir[core.source_hir];
    uint function_count = min(gParams.function_capacity,
        min(target_function_count[0u], semantic_lir_function_total[0u]));
    uint function_index = function_id < gParams.function_capacity
        ? target_function_index_by_semantic[function_id] : INVALID;
    if (function_index >= function_count)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
        if (core.source_hir == 11u)
        {
            // TEMP diagnostic: encode the missing function lookup in the
            // status packet while isolating loop lowering.
            InterlockedMin(lowering_status[0u].available_capacity,
                2000u + min(function_index, 999u));
            InterlockedMin(lowering_status[0u].required_capacity,
                min(function_id, 999u));
        }
        return;
    }
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    uint saved_mask = x86_saved_gpr_mask_by_function[function_id];
    uint bytes = instruction_bytes(core, operands, locations, saved_mask);
    bool supported_zero = core.op == X86_LIR_OP_LABEL ||
        core.op == X86_LIR_OP_AGGREGATE_RESULT_SLOT ||
        core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD;
    if (bytes == 0u && !supported_zero)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_ARG && operands.a >= total)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
        if (core.source_hir == 11u)
        {
            InterlockedMin(lowering_status[0u].available_capacity,
                6000u + min(operands.a, 999u));
            InterlockedMin(lowering_status[0u].required_capacity,
                min(total, 999u));
        }
    }
    if ((core.op == X86_LIR_OP_ARRAY_INIT && operands.a >= total) ||
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
    uint hidden_sret = 0u;
    if (semantic_function.param_count + hidden_sret > 6u)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (row == function.instruction_start)
        bytes += 11u + x86_saved_gpr_count(saved_mask) * 7u +
            param_store_bytes(semantic_function, hidden_sret);
    if (row + 1u == function.instruction_start + function.instruction_count)
        bytes += 4u + x86_saved_gpr_count(saved_mask) * 7u;
    if (core.source_hir == 11u && core.op == X86_LIR_OP_CALL_ARG &&
        operands.b >= 6u)
    {
        // TEMP diagnostic for the first sample-suite loop lowering failure.
        InterlockedMin(lowering_status[0u].available_capacity,
            5000u + operands.b);
        InterlockedMin(lowering_status[0u].required_capacity, operands.a);
    }
    target_byte_length[row] = bytes;
}
