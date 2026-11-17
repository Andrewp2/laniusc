import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_commit_audit;
import type_checker.trait_solver.proof_frontier_stages;
import gpu_index;

// One lane per Work; the last workgroup commits (proof_commit_audit.slang).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID, uint3 ltid : SV_GroupThreadID)
{
    if (trait_solver_params.phase != 55u || proof_store_params.phase != 55u) return;
    if (dtid.z != 0u) return;
    pps_stage_audit_substitutions(linear_dispatch_thread_id_2d(dtid, 16776960u));
    if (pca_last_group(ltid.x)) pps_stage_commit_substitutions();
}
