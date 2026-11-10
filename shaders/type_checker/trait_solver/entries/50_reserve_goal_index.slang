import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_frontier_stages;

// One thread, after 50_audit_work.
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 50u || proof_store_params.phase != 50u) return;
    if (any(thread_id != uint3(0u, 0u, 0u))) return;
    pps_stage_reserve_goal_index();
}
