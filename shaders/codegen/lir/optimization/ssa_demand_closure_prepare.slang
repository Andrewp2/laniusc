// Freezes the seed prefix: the closure appends its rows after it.

import codegen.optimization_ir;

StructuredBuffer<uint> opt_ir_ssa_demand_total;
RWStructuredBuffer<uint> opt_ir_ssa_demand_seed_total;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (any(dtid != uint3(0u))) return;
    uint seed_total = opt_ir_ssa_demand_total[0u];
    opt_ir_ssa_demand_seed_total[0u] = seed_total;
}
