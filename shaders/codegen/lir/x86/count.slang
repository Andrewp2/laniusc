import codegen.lir.x86.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_instruction;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_instruction;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> target_lir_count;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint scheduled_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (scheduled_row >= gParams.semantic_capacity) return;
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
        ? semantic_lir_call_arg_count_by_instruction[semantic_row]
        : 0u;
    uint argument_rows = 0u;
    uint argument_start = semantic_lir_call_arg_start_by_instruction[semantic_row];
    for (uint arg_i = 0u; arg_i < min(argument_count, 6u); arg_i += 1u)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[argument_start + arg_i];
        SemanticLirCore argument_core;
        argument_core.op = 0u;
        argument_core.type_id = 0u;
        argument_core.type_ref_tag = SEMANTIC_TYPE_REF_INVALID;
        argument_core.type_ref_payload = 0xffffffffu;
        argument_core.source_hir = 0xffffffffu;
        argument_core.flags = 0u;
        if (argument.value_instruction < gParams.semantic_capacity)
            argument_core = semantic_lir_core[argument.value_instruction];
        argument_rows += x86_semantic_type_is_string(argument_core) ? 2u : 1u;
    }
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    uint result_words = core.op == SEMANTIC_LIR_OP_CALL &&
        operands.a < function_count ? semantic_lir_functions[operands.a].result_word_count : 0u;
    uint owner = semantic_lir_schedule[semantic_row].function_id;
    uint return_words = core.op == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_word_count : 0u;
    target_lir_count[scheduled_row] =
        x86_lir_count(core, operands) + argument_rows + result_words + return_words;
}
