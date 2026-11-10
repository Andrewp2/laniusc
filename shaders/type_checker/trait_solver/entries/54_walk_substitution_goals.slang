import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_substitution_walk;
import type_checker.trait_solver.proof_frontier_stages;

// Substitution walk up to the head match: proof work admission (phase 54)
// or implementation proof admission (phase 59).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    uint phase = proof_store_params.phase;
    if (trait_solver_params.phase != phase ||
        (phase != PPS_WALK_PHASE_WORK && phase != PPS_WALK_PHASE_PROOFS)) return;
    pps_stage_walk_goals(thread_id.x, phase);
}
