// Admit function entries. All other reachable blocks remain unresolved until
// every reachable forward predecessor has published its completed parent.

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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_reachable;
StructuredBuffer<uint> opt_ir_forward_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<uint> opt_ir_reachability_work_state;
RWStructuredBuffer<uint> opt_ir_reachability_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= block_total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    uint function_total = min(semantic_function_total[0u], gParams.hir_capacity);
    if (block.function_id >= function_total)
    {
        report_structure_failure(block_id);
        return;
    }
    uint count = opt_ir_forward_predecessor_count_by_block[block_id];
    bool entry = block_id == opt_ir_functions[block.function_id].entry_block;
    bool reachable = opt_ir_reachable[block_id] != 0u;
    if (!reachable)
    {
        if (entry || count != 0u) report_structure_failure(block_id);
        opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_UNREACHABLE;
        return;
    }
    opt_ir_immediate_dominator[block_id] = entry
        ? block_id : OPT_IR_DOMINATOR_UNRESOLVED;
    if (entry ? count != 0u : count == 0u)
    {
        report_structure_failure(block_id);
        return;
    }
    if (!entry) return;
    uint required = 0u;
    if (!ssa_work_publish(block_id, gParams.block_capacity,
            opt_ir_reachability_work_state,
            opt_ir_reachability_work_queue, required))
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, required);
        lowering_status[0u].available_capacity = gParams.block_capacity;
    }
}
