import codegen.lir.x86.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_instruction;
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
    uint argument_rows = (core.op == SEMANTIC_LIR_OP_CALL ||
                          core.op == SEMANTIC_LIR_OP_CALL_HOST ||
                          core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC)
        ? semantic_lir_call_arg_count_by_instruction[semantic_row]
        : 0u;
    target_lir_count[scheduled_row] =
        x86_lir_count(core, semantic_lir_operands[semantic_row]) + argument_rows;
}
