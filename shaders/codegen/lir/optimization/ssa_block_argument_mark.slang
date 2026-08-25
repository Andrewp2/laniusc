// Counts pruned block arguments and their predecessor inputs from the
// canonical sparse block-entry demand relation.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_canonical_lookup;
import gpu_index;

struct Params
{
    uint block_capacity;
    uint edge_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint declaration_block_capacity;
    uint demand_capacity;
    uint worker_count;
    uint max_radix_blocks;
    uint incoming_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_flag;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_count;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = opt_ir_active_ssa_demand_total(gParams.demand_capacity);
    if (row >= total) return;

    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    OptIrSsaDemand demand = opt_ir_canonical_ssa_demand(row, total);
    bool valid = demand.declaration < gParams.declaration_capacity &&
        demand.block < block_total;
    uint predecessor_count = 0u;
    if (valid)
    {
        uint begin = opt_ir_predecessor_prefix[demand.block];
        uint end = demand.block + 1u < block_total
            ? opt_ir_predecessor_prefix[demand.block + 1u]
            : edge_total;
        valid = begin <= end && end <= edge_total;
        if (valid)
        {
            for (uint predecessor_i = begin;
                 predecessor_i < end;
                 ++predecessor_i)
            {
                uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
                valid = edge_id < edge_total;
                if (!valid) break;
                OptIrEdge edge = opt_ir_edges[edge_id];
                valid = opt_ir_edge_to_block(edge.packed_target) ==
                    demand.block && edge.from_block < block_total;
                if (!valid) break;
                if (opt_ir_reachable[edge.from_block] != 0u)
                    predecessor_count += 1u;
            }
        }
    }

    bool is_join = valid && predecessor_count > 1u;
    opt_ir_ssa_block_argument_flag[row] = is_join ? 1u : 0u;
    opt_ir_ssa_block_argument_incoming_count[row] =
        is_join ? predecessor_count : 0u;
    if (!valid) report_structure_failure(row);
}
