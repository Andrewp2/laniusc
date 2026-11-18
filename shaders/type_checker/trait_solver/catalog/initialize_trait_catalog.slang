import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_stages;
import type_checker.trait_solver.admission_group;

// One workgroup admits the output layout and directories (admission_group),
// then its first lane initializes.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 lane : SV_GroupThreadID, uint3 group : SV_GroupID)
{
    if (trait_solver_params.phase != 0u) return;
    if (any(group != uint3(0u, 0u, 0u)) ||
        trait_solver_params.dispatch_first != 0u || trait_solver_params.dispatch_count != 1u) return;
    SolverStatus layout; SolverStatus directories;
    ts_admit_group(lane.x, layout, directories);
    if (lane.x == 0u) ts_catalog_initialize_admitted(layout, directories);
}
