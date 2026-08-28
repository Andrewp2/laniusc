// Seeds exact CFG reachability from every function entry. A bounded global
// queue is shared by persistent GPU workers; each block is admitted once.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_block_total;
RWStructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_reachability_work_state;
RWStructuredBuffer<uint> opt_ir_reachability_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.block_capacity;
}

void report_structure_failure(uint function_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_SEED, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row,
        function_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(
        dtid, DISPATCH_X_STRIDE);
    uint function_total = min(semantic_function_total[0u],
        gParams.hir_capacity);
    if (function_id >= function_total) return;

    uint block_total = min(opt_ir_block_total[0u],
        gParams.block_capacity);
    uint entry = opt_ir_functions[function_id].entry_block;
    if (entry >= block_total)
    {
        report_structure_failure(function_id);
        return;
    }
    uint prior;
    InterlockedCompareExchange(opt_ir_reachable[entry], 0u, 1u, prior);
    if (prior != 0u) return;
    uint required = 0u;
    if (!ssa_work_publish(entry, gParams.block_capacity,
            opt_ir_reachability_work_state,
            opt_ir_reachability_work_queue, required))
        report_capacity(required);
}
