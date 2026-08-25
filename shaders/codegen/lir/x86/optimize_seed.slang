// Admits every observable OptIR root to the exact global liveness queue.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;
import atomics;
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
RWStructuredBuffer<uint> x86_live_by_semantic;
RWStructuredBuffer<uint> x86_liveness_work_state;
RWStructuredBuffer<uint> x86_liveness_work_queue;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool observable_root(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    if ((core.flags & (SEMANTIC_LIR_FLAG_UNSUPPORTED |
                       SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE)) != 0u)
        return true;
    return op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE || semantic_lir_is_call(op) ||
        (op >= SEMANTIC_LIR_OP_BLOCK_BEGIN && op <= SEMANTIC_LIR_OP_RETURN) ||
        op == SEMANTIC_LIR_OP_DROP || op == SEMANTIC_LIR_OP_LOAD ||
        op == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
        op == SEMANTIC_LIR_OP_DIV || op == SEMANTIC_LIR_OP_REM;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= total || !observable_root(opt_ir_core[row])) return;
    uint prior = atomic_u32_compare_exchange(
        x86_live_by_semantic, row, 0u, X86_SEMANTIC_LIVE);
    if (prior != 0u) return;
    uint required;
    ssa_work_publish(row, gParams.semantic_capacity,
        x86_liveness_work_state, x86_liveness_work_queue, required);
}
