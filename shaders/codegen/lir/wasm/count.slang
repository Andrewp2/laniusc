import codegen.lir.wasm.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint semantic_start; uint page_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
RWStructuredBuffer<uint> target_lir_count;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.semantic_start + page_row;
    uint count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (row >= count)
    {
        target_lir_count[row] = 0u;
        return;
    }
    uint semantic_row = semantic_schedule_order[row];
    SemanticLirCore core = semantic_lir_core[semantic_row];
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    bool call_index_base = core.op == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u &&
        operands.a < count &&
        (semantic_lir_core[operands.a].op == SEMANTIC_LIR_OP_CALL ||
         semantic_lir_core[operands.a].op == SEMANTIC_LIR_OP_CALL_SYMBOL);
    target_lir_count[row] = wasm_lir_count(
        core, operands, call_index_base);
}
