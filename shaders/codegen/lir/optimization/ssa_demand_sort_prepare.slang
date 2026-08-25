// Produces the indirect row-domain dispatch for canonical demand ordering.

import radix;

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
RWStructuredBuffer<uint> opt_ir_ssa_demand_radix_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (any(dtid != uint3(0u))) return;
    uint total = min(opt_ir_ssa_demand_total[0u], gParams.demand_capacity);
    uint blocks = max(radix_active_block_count(
        total, gParams.max_radix_blocks, WG_SIZE), 1u);
    opt_ir_ssa_demand_radix_dispatch_args[0u] = min(blocks, MAX_GROUPS_X);
    opt_ir_ssa_demand_radix_dispatch_args[1u] =
        (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    opt_ir_ssa_demand_radix_dispatch_args[2u] = 1u;
}
