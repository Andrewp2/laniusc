// Materializes the radix permutation into one physically canonical sparse
// demand relation. Later SSA passes can then use dense rows directly instead
// of carrying the order indirection through the rest of the optimizer.

import codegen.lowering_ir;
import codegen.optimization_ir;
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
StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
StructuredBuffer<uint> opt_ir_ssa_demand_order;
RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_canonical_demands_tmp;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_ssa_demand_total[0u], gParams.demand_capacity);
    if (row >= total) return;

    uint source_row = opt_ir_ssa_demand_order[row];
    OptIrSsaDemand demand;
    demand.declaration = INVALID;
    demand.block = INVALID;
    if (source_row >= total)
    {
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
        InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    }
    else
    {
        demand = opt_ir_ssa_demands[source_row];
    }
    opt_ir_ssa_canonical_demands_tmp[row] = demand;
}
