import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.admission_group;
import type_checker.trait_solver.proof_publication.proof_store_lifecycle;

// One workgroup admits the batch and proof store layouts.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 lane : SV_GroupThreadID, uint3 group : SV_GroupID)
{
    if (trait_solver_params.phase != 12u) return;
    if (any(group != uint3(0u, 0u, 0u)) ||
        trait_solver_params.dispatch_first != 0u || trait_solver_params.dispatch_count != 1u) return;
    SolverStatus layout; SolverStatus directories;
    ts_admit_group(lane.x, layout, directories);
    if (lane.x == 0u) ts_batch_initialize_admitted(layout, directories);
    // Only lane zero reads the batch receipt while initializing the store.
    pps_initialize_store_group(lane.x);
}
