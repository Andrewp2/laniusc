import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_commit_audit;
import type_checker.trait_solver.normalization.proof_normalization_stages;
import gpu_index;

// One lane per Work; the last workgroup commits (proof_commit_audit.slang).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID, uint3 ltid : SV_GroupThreadID)
{
    if (trait_solver_params.phase != 45u || proof_store_params.phase != 45u) return;
    if (dtid.z != 0u) return;
    pps_stage_audit_normalized_terms(linear_dispatch_thread_id_2d(dtid, 16776960u));
    if (pca_last_group(ltid.x)) pps_stage_commit_normalized_terms();
}
