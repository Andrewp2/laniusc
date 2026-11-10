import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_normalization_stages;

// One thread, after 47_audit_normalized_goals.
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 47u || proof_store_params.phase != 47u) return;
    if (any(thread_id != uint3(0u, 0u, 0u))) return;
    pps_stage_commit_normalized_goals();
}
