// Independently validates the completed sparse demand closure and its
// capacity-derived canonical ordering.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_lookup;
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
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_total;
StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
StructuredBuffer<uint> opt_ir_ssa_demand_order;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

OptIrSsaDemand ordered_demand(uint dense_row, uint total)
{
    OptIrSsaDemand invalid;
    invalid.declaration = INVALID;
    invalid.block = INVALID;
    if (dense_row >= total) return invalid;
    uint source_row = opt_ir_ssa_demand_order[dense_row];
    return source_row < total ? opt_ir_ssa_demands[source_row] : invalid;
}

uint lower_bound_demand(uint declaration, uint block, uint total)
{
    OptIrSsaDemand needle;
    needle.declaration = declaration;
    needle.block = block;
    uint lo = 0u;
    uint hi = total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (opt_ir_ssa_demand_less(ordered_demand(mid, total), needle))
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

bool contains_demand(uint declaration, uint block, uint total)
{
    uint row = lower_bound_demand(declaration, block, total);
    OptIrSsaDemand found = ordered_demand(row, total);
    return found.declaration == declaration && found.block == block;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_ssa_demand_total[0u], gParams.demand_capacity);
    uint seed_total = min(opt_ir_ssa_demand_seed_total[0u], total);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint access_total = opt_ir_active_access_total(gParams.access_capacity);
    uint declaration_block_total = opt_ir_active_declaration_block_total(
        gParams.declaration_block_capacity);
    bool valid = true;

    if (row < total)
    {
        OptIrSsaDemand demand = ordered_demand(row, total);
        valid = demand.declaration < gParams.declaration_capacity &&
            demand.block < block_total &&
            (row == 0u || opt_ir_ssa_demand_less(
                ordered_demand(row - 1u, total), demand));
        if (valid)
        {
            uint predecessor_start = opt_ir_predecessor_prefix[demand.block];
            uint predecessor_end = demand.block + 1u < block_total
                ? opt_ir_predecessor_prefix[demand.block + 1u]
                : edge_total;
            valid = predecessor_start <= predecessor_end &&
                predecessor_end <= edge_total;
            for (uint predecessor_i = predecessor_start;
                 valid && predecessor_i < predecessor_end;
                 ++predecessor_i)
            {
                uint edge_id = opt_ir_predecessor_edge_ids[predecessor_i];
                valid = edge_id < edge_total;
                if (!valid) break;
                OptIrEdge edge = opt_ir_edges[edge_id];
                valid = opt_ir_edge_to_block(edge.packed_target) ==
                    demand.block &&
                    edge.from_block < block_total;
                if (valid &&
                    opt_ir_reachable[edge.from_block] == 0u)
                    continue;
                if (valid && opt_ir_outgoing_local_definition(
                        demand.declaration,
                        edge.from_block,
                        declaration_block_total,
                        access_total) == INVALID)
                    valid = contains_demand(
                        demand.declaration, edge.from_block, total);
            }
        }
    }

    // Initial upward-exposed reads must remain members after closure and sort.
    if (valid && row < seed_total)
    {
        OptIrSsaDemand seed = opt_ir_ssa_demands[row];
        valid = contains_demand(seed.declaration, seed.block, total);
    }

    if (!valid) report_structure_failure(row);
}
