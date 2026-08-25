// Commits physically ordered demand rows to the canonical relation after its
// publication-order contents have been validated and are no longer needed.

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
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_canonical_demands_tmp;
RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_ssa_demand_total[0u], gParams.demand_capacity);
    if (row < total)
        opt_ir_ssa_demands[row] = opt_ir_ssa_canonical_demands_tmp[row];
}
