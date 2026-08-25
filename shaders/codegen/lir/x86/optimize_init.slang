// Initializes the persistent parallel liveness market and the inexpensive
// per-node value facts. No invocation traverses another node.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint worker_count;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
RWStructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
RWStructuredBuffer<uint> x86_liveness_work_state;
RWStructuredBuffer<uint> x86_liveness_work_queue;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row < 4u) x86_liveness_work_state[row] = 0u;
    if (row < gParams.semantic_capacity)
        x86_liveness_work_queue[row] = 0u;

    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= total) return;
    X86ValueAnalysis value;
    value.value = 0u;
    value.known = 0u;
    value.replacement = row;
    OptIrNodeCore core = opt_ir_core[row];
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I32)
    {
        value.value = opt_ir_operands[row].a;
        value.known = 1u;
    }
    x86_value_by_semantic[row] = value;
}
