import codegen.lir.x86.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint semantic_start; uint page_capacity; uint reserved; };
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
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
RWStructuredBuffer<uint> target_lir_count;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint scheduled_row = gParams.semantic_start + page_row;
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (scheduled_row >= total)
    {
        target_lir_count[scheduled_row] = 0u;
        return;
    }
    uint semantic_row = semantic_schedule_order[scheduled_row];
    SemanticLirCore core = semantic_lir_core[semantic_row];
    uint argument_count = (core.op == SEMANTIC_LIR_OP_CALL ||
                          core.op == SEMANTIC_LIR_OP_CALL_HOST ||
                          core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
                          core.op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        ? semantic_lir_call_arg_count_by_hir[core.source_hir]
        : 0u;
    uint argument_rows = 0u;
    uint argument_start = semantic_lir_call_arg_start_by_hir[core.source_hir];
    for (uint arg_i = 0u; arg_i < min(argument_count, 6u); arg_i += 1u)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[argument_start + arg_i];
        argument_rows +=
            (argument.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u
                ? 2u : 1u;
    }
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    uint result_words = core.op == SEMANTIC_LIR_OP_CALL &&
        operands.a < function_count ? semantic_lir_functions[operands.a].result_word_count :
        core.op == SEMANTIC_LIR_OP_CALL_SYMBOL ? core.value_word_count : 0u;
    uint owner = semantic_function_id_by_hir[semantic_owner_by_instruction[semantic_row]];
    uint return_words = core.op == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_word_count : 0u;
    uint copy_words = 0u;
    if ((core.op == SEMANTIC_LIR_OP_VALUE_SET ||
         core.op == SEMANTIC_LIR_OP_STORE) &&
        x86_semantic_type_is_aggregate(core) && operands.b < total)
    {
        SemanticLirCore value_core = semantic_lir_core[operands.b];
        SemanticLirOperands value_operands = semantic_lir_operands[operands.b];
        uint call_words = value_core.op == SEMANTIC_LIR_OP_CALL &&
            value_operands.a < function_count
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
        copy_words = max(max(core.value_word_count, call_words),
            x86_aggregate_value_word_count(value_core, value_operands));
    }
    uint operation_rows = x86_lir_count(core, operands);
    if (core.op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        uint element_total = semantic_lir_aggregate_element_total[0u];
        uint words = 0u;
        for (uint element_i = 0u; element_i < operands.b; element_i += 1u)
        {
            uint row = operands.a + element_i;
            if (row >= element_total) break;
            words += semantic_lir_aggregate_elements[row].word_count;
        }
        operation_rows = 1u + words;
    }
    target_lir_count[scheduled_row] = operation_rows +
        argument_rows + result_words + return_words + copy_words;
}
