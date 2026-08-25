import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
RWStructuredBuffer<uint> x86_object_relocation_flag;
RWStructuredBuffer<uint> x86_object_symbol_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = opt_ir_total[0u];
    if (row >= total) return;
    uint op = opt_ir_op(opt_ir_core[semantic_schedule_order[row]]);
    x86_object_relocation_flag[row] =
        op == SEMANTIC_LIR_OP_CALL_SYMBOL || op == SEMANTIC_LIR_OP_CONST_STRING ? 1u : 0u;
    x86_object_symbol_flag[row] = op == SEMANTIC_LIR_OP_CALL_SYMBOL ? 1u : 0u;
}
