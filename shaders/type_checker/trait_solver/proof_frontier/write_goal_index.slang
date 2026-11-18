import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_commit_audit;
import type_checker.trait_solver.proof_frontier.proof_frontier_stages;
import shared.buffers.gpu_index;

// One lane per pending Work row, after the goal-index reservation; the last
// workgroup commits the Work (proof_commit_audit.slang).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID, uint3 ltid : SV_GroupThreadID)
{
    if (trait_solver_params.phase != 50u || proof_store_params.phase != 50u) return;
    if (dtid.z != 0u) return;
    pps_stage_write_goal_index(linear_dispatch_thread_id_2d(dtid, 16776960u));
    if (pca_last_group(ltid.x)) pps_stage_commit_work();
}
