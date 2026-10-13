// Count reachable forward dependencies. The scheduling position orders the
// acyclic graph; retreating edges are independently checked after resolution.

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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_forward_predecessor_count_by_block;
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

    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    if (edge.from_block >= block_total || to_block >= block_total)
    {
        report_structure_failure(edge_id);
        return;
    }
    OptIrBlock from = opt_ir_blocks[edge.from_block];
    OptIrBlock to = opt_ir_blocks[to_block];
    bool backward = to.position_start <= from.position_start;
    if (from.function_id != to.function_id || backward !=
        ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u))
    {
        report_structure_failure(edge_id);
        return;
    }
    if (backward || opt_ir_reachable[edge.from_block] == 0u ||
        opt_ir_reachable[to_block] == 0u)
        return;
    InterlockedAdd(opt_ir_forward_predecessor_count_by_block[to_block], 1u);
}
