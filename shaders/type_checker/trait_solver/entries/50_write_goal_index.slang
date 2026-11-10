import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_frontier_stages;
import gpu_index;

// One lane per pending Work row, after 50_reserve_goal_index.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 50u || proof_store_params.phase != 50u) return;
    if (dtid.z != 0u) return;
    pps_stage_write_goal_index(linear_dispatch_thread_id_2d(dtid, 16776960u));
}
