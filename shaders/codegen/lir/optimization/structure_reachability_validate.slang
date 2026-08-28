// Independently checks the reachability fixed point against the reverse CFG.

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
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_reachability_work_state;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_VALIDATE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u],
        gParams.block_capacity);
    if (block >= block_total) return;
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);

    uint function_total = min(semantic_function_total[0u],
        gParams.hir_capacity);
    uint function_id = opt_ir_blocks[block].function_id;
    bool valid = function_id < function_total;
    bool entry = valid &&
        opt_ir_functions[function_id].entry_block == block;

    uint begin = opt_ir_predecessor_prefix[block];
    uint end = block + 1u < block_total
        ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
    valid = valid && begin <= end && end <= edge_total;
    bool reachable_predecessor = false;
    for (uint row = begin; valid && row < end; ++row)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[row];
        valid = edge_id < edge_total;
        if (!valid) break;
        OptIrEdge edge = opt_ir_edges[edge_id];
        valid = edge.from_block < block_total &&
            opt_ir_edge_to_block(edge.packed_target) == block;
        reachable_predecessor = reachable_predecessor ||
            (valid && opt_ir_reachable[edge.from_block] != 0u);
    }
    bool expected = entry || reachable_predecessor;
    valid = valid && (opt_ir_reachable[block] != 0u) == expected;
    if (block == 0u)
        valid = valid &&
            opt_ir_reachability_work_state[SSA_WORK_HEAD] ==
                opt_ir_reachability_work_state[SSA_WORK_TAIL] &&
            opt_ir_reachability_work_state[SSA_WORK_OUTSTANDING] == 0u;
    if (!valid) report_structure_failure(block);
}
