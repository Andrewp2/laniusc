// Freezes the seed prefix and initializes the shared sparse work-market state.

import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;

StructuredBuffer<uint> opt_ir_ssa_demand_total;
RWStructuredBuffer<uint> opt_ir_ssa_demand_seed_total;
RWStructuredBuffer<uint> opt_ir_ssa_work_state;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (any(dtid != uint3(0u))) return;
    uint seed_total = opt_ir_ssa_demand_total[0u];
    opt_ir_ssa_demand_seed_total[0u] = seed_total;
    opt_ir_ssa_work_state[SSA_WORK_HEAD] = 0u;
    opt_ir_ssa_work_state[SSA_WORK_TAIL] = seed_total;
    opt_ir_ssa_work_state[SSA_WORK_OUTSTANDING] = seed_total;
    opt_ir_ssa_work_state[SSA_WORK_RESERVED] = 0u;
}
