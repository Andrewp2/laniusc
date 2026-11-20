import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_store_lifecycle;
import type_checker.trait_solver.proof_frontier.proof_work;
import type_checker.trait_solver.proof_frontier.proof_selection;

// One lane per Work of the step: its proof, substitution and child Works.
[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 85u || proof_store_params.phase != 85u) return;
    uint work; SolverStatus status;
    if (!pps_wave_lane(thread_id.x, work)) return;
    if (!ts_bind_scratch(thread_id.x, work, status)) { pps_store_failure(status); return; }
    pps_store_failure(pps_write_proof(work));
}
