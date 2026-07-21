import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<uint> scheduled_function_id;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> target_byte_length;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint param_store_bytes(uint count)
{
    // Every incoming GPR parameter is retained as a full machine word. This
    // keeps aggregate references intact while scalar consumers continue to
    // read the low dword from the same frame slot.
    if (count <= 4u) return count * 7u;
    return 28u + (min(count, 6u) - 4u) * 8u;
}

uint instruction_bytes(X86LirCore core, X86LirOperands operands)
{
    if (core.op == X86_LIR_OP_IMM_I32) return 11u;
    if (core.op == X86_LIR_OP_ALIAS) return 14u;
    if (core.op == X86_LIR_OP_STORE_LOCAL) return 12u;
    if (core.op == X86_LIR_OP_BINARY)
    {
        if (operands.a >= X86_LIR_BINARY_ADD_F32 && operands.a <= X86_LIR_BINARY_DIV_F32)
            return 28u;
        if (operands.a == X86_LIR_BINARY_MUL_I32) return 21u;
        if (operands.a == X86_LIR_BINARY_DIV_I32) return 21u;
        if (operands.a == X86_LIR_BINARY_REM_I32) return 23u;
        return 20u;
    }
    if (core.op == X86_LIR_OP_COMPARE)
        return (operands.metadata & 0xffu) == 5u ? 31u : 26u;
    if (core.op == X86_LIR_OP_UNARY)
        return operands.a == X86_LIR_UNARY_NEG_I32 ? 14u
             : operands.a == X86_LIR_UNARY_NOT_BOOL ? 21u
             : operands.a == X86_LIR_UNARY_NEG_F32 ? 17u : 0u;
    if (core.op == X86_LIR_OP_RETURN)
        return operands.a == INVALID ? 4u
            : (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u ? 9u : 8u;
    if (core.op == X86_LIR_OP_RETURN_VOID) return 4u;
    if (core.op == X86_LIR_OP_CALL_ARG)
    {
        if (operands.b >= 6u) return 0u;
        bool aggregate_reference =
            (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        return aggregate_reference ? 10u : operands.b < 4u ? 8u : 9u;
    }
    if (core.op == X86_LIR_OP_CALL)
        return (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u ? 12u : 11u;
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a == 28u) return 12u;
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a == 29u) return 7u;
    if (core.op == X86_LIR_OP_ARRAY_ADDR) return 14u;
    if (core.op == X86_LIR_OP_ARRAY_INIT) return 12u;
    if (core.op == X86_LIR_OP_INDEX_LOAD) return 25u;
    if (core.op == X86_LIR_OP_FIELD_LOAD) return 19u;
    if (core.op == X86_LIR_OP_BRANCH) return operands.a == INVALID ? 5u : 14u;
    if (core.op == X86_LIR_OP_LABEL) return 0u;
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= gParams.target_capacity) return;
    target_byte_length[row] = 0u;
    if (row >= total) return;
    uint function_id = scheduled_function_id[row];
    uint function_count = min(gParams.function_capacity,
        min(target_function_count[0u], semantic_lir_function_total[0u]));
    uint function_index = function_id < gParams.function_capacity
        ? target_function_index_by_semantic[function_id] : INVALID;
    if (function_index >= function_count)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        return;
    }
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    X86LirCore core = target_lir_core[row];
    X86LirOperands operands = target_lir_operands[row];
    uint bytes = instruction_bytes(core, operands);
    if (core.op == X86_LIR_OP_STORE_LOCAL &&
        (operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        bytes = 14u;
    bool supported_zero = core.op == X86_LIR_OP_LABEL;
    if (bytes == 0u && !supported_zero)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_ARG && operands.a >= total)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if ((core.op == X86_LIR_OP_ARRAY_INIT && operands.a >= total) ||
        (core.op == X86_LIR_OP_INDEX_LOAD &&
         (operands.a >= total || operands.b >= total)) ||
        (core.op == X86_LIR_OP_FIELD_LOAD && operands.a >= total))
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
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a != 28u && operands.a != 29u)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (semantic_function.param_count > 6u)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    if (row == function.instruction_start)
        bytes += 11u + param_store_bytes(semantic_function.param_count);
    if (row + 1u == function.instruction_start + function.instruction_count)
        bytes += 4u;
    target_byte_length[row] = bytes;
}
