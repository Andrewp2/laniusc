// Counts incoming CFG edges for every dense basic block.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
RWStructuredBuffer<uint> opt_ir_predecessor_count_by_block;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint edge_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, edge_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint edge_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    if (edge_id >= total) return;

    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    if (edge.from_block >= gParams.block_capacity ||
        to_block >= gParams.block_capacity)
    {
        report_structure_failure(edge_id);
        return;
    }
    InterlockedAdd(opt_ir_predecessor_count_by_block[to_block], 1u);
}
