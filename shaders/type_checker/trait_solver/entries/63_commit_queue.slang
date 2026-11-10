import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_frontier_stages;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 63u || proof_store_params.phase != 63u) return;
    pps_stage_commit_queue();
}
