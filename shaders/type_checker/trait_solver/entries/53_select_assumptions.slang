import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_frontier_stages;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 53u || proof_store_params.phase != 53u) return;
    pps_stage_select_assumptions(thread_id.x);
}
