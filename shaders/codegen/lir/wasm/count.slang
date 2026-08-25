import codegen.lir.wasm.common;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint semantic_start; uint page_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
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
    uint count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= count)
    {
        target_lir_count[row] = 0u;
        return;
    }
    uint semantic_row = semantic_schedule_order[row];
    OptIrNodeCore core = opt_ir_core[semantic_row];
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];
    bool call_index_base = opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u &&
        operands.a < count &&
        (opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_CALL ||
         opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_CALL_SYMBOL);
    bool direct_field_store_receiver = opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u &&
        operands.a < count &&
        opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_VALUE_GET;
    target_lir_count[row] = wasm_lir_count(
        core, operands, call_index_base, direct_field_store_receiver);
}
