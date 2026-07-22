import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint semantic_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<uint> target_semantic_origin;
StructuredBuffer<uint> semantic_to_target_start;
StructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;
RWStructuredBuffer<uint> scheduled_function_id;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint target_value(uint semantic_row, uint total)
{
    uint target_row = semantic_row < gParams.semantic_capacity
        ? semantic_to_target_start[semantic_row] : INVALID;
    return target_row < total ? target_row : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= total) return;

    X86LirCore core = target_lir_core[row];
    X86LirOperands operands = target_lir_operands[row];
    if (core.result_or_target != INVALID) core.result_or_target = row;
    if (core.op == X86_LIR_OP_BINARY || core.op == X86_LIR_OP_COMPARE)
    {
        operands.b = target_value(operands.b, total);
        operands.c = target_value(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_UNARY)
        operands.b = target_value(operands.b, total);
    else if (core.op == X86_LIR_OP_RETURN)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        uint base = target_value(operands.a, total);
        operands.a = base < total && operands.c < total - base
            ? base + operands.c : INVALID;
        operands.c = 0u;
    }
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
        operands.b = target_value(operands.b, total);
    else if (core.op == X86_LIR_OP_ARRAY_INIT)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        operands.a = target_value(operands.a, total);
        operands.b = target_value(operands.b, total);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
        operands.a = target_value(operands.a, total);
    if (core.op == X86_LIR_OP_BRANCH)
    {
        operands.a = target_value(operands.a, total);
        uint target = target_value(operands.b, total);
        operands.b = target < total ? target + operands.c : INVALID;
        operands.c = 0u;
    }

    target_lir_core[row] = core;
    target_lir_operands[row] = operands;
    uint semantic_row = target_semantic_origin[row];
    scheduled_function_id[row] = semantic_row < gParams.semantic_capacity
        ? semantic_lir_schedule[semantic_row].function_id : INVALID;
}
