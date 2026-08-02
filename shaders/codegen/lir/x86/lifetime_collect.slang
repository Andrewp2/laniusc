import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
RWStructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_clobber_by_position;

static const uint DISPATCH_X_STRIDE = 16776960u;

void record_use(uint value, uint position, uint total)
{
    if (value >= total) return;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[value], position, ignored);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (position >= total) return;
    uint row = semantic_schedule_order[position];
    if (row >= total) return;
    x86_position_by_semantic[row] = position;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[row], position, ignored);

    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    uint op = core.op;
    if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        if (op == SEMANTIC_LIR_OP_STORE &&
            (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u)
        {
            record_use(operands.a, position, total);
            if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
                record_use(operands.b, position, total);
            record_use(operands.c, position, total);
        }
        else record_use(operands.b, position, total);
    }
    else if ((op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
             op == SEMANTIC_LIR_OP_LOGICAL_AND ||
             op == SEMANTIC_LIR_OP_LOGICAL_OR)
    {
        record_use(operands.a, position, total);
        record_use(operands.b, position, total);
    }
    else if (op == SEMANTIC_LIR_OP_NEGATE ||
             op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
             op == SEMANTIC_LIR_OP_CONVERT ||
             op == SEMANTIC_LIR_OP_DROP ||
             op == SEMANTIC_LIR_OP_ADDRESS ||
             op == SEMANTIC_LIR_OP_RETURN)
        record_use(operands.a, position, total);
    else if (op == SEMANTIC_LIR_OP_LOAD)
    {
        record_use(operands.a, position, total);
        if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
            record_use(operands.b, position, total);
    }
    else if (op == SEMANTIC_LIR_OP_AGGREGATE_COPY)
    {
        record_use(operands.a, position, total);
        record_use(operands.b, position, total);
    }
    else if (op == SEMANTIC_LIR_OP_IF_BEGIN ||
             op == SEMANTIC_LIR_OP_BRANCH_IF)
        record_use(operands.a, position, total);

    if (op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_HOST ||
        op == SEMANTIC_LIR_OP_CALL_INTRINSIC || op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        x86_clobber_by_position[position] = 1u;
}
