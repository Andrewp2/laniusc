// Validates compact predecessor ranges against the canonical forward CFG.

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
StructuredBuffer<uint> opt_ir_predecessor_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_count_by_block;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_cursor;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
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
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    if (block_id >= block_total) return;

    uint start = opt_ir_predecessor_prefix[block_id];
    uint count = opt_ir_predecessor_count_by_block[block_id];
    uint end = start + count;
    bool valid = opt_ir_predecessor_total[0u] == edge_total &&
        end >= start && end <= edge_total &&
        opt_ir_predecessor_cursor[block_id] == end;
    for (uint row = start; valid && row < end; ++row)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[row];
        valid = edge_id < edge_total &&
            opt_ir_edge_to_block(opt_ir_edges[edge_id].packed_target) ==
                block_id;
    }
    if (!valid) report_structure_failure(block_id);
}
