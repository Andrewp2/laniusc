// Scatters canonical CFG edge IDs into predecessor ranges.

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
RWStructuredBuffer<uint> opt_ir_predecessor_cursor;
RWStructuredBuffer<uint> opt_ir_predecessor_edge_ids;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.edge_capacity;
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
    if (to_block >= gParams.block_capacity) return;
    uint destination;
    InterlockedAdd(opt_ir_predecessor_cursor[to_block], 1u, destination);
    if (destination >= gParams.edge_capacity)
    {
        report_capacity(destination + 1u);
        return;
    }
    opt_ir_predecessor_edge_ids[destination] = edge_id;
}
