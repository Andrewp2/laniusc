import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_index;

// One workgroup per implementation: 256 dispatch rows each
// (ts_catalog_check_coherence_group).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 lane : SV_GroupThreadID)
{
    if (trait_solver_params.phase != 10u) return;
    if (group.y != 0u || group.z != 0u) return;
    if (group.x * TS_COHERENCE_LANES >= trait_solver_params.dispatch_count) return;
    ts_catalog_check_coherence_group(group.x, lane.x);
}
