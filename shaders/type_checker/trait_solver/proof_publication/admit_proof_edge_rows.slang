import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_commit_audit;
import type_checker.trait_solver.proof_frontier.proof_frontier_stages;

// One thread per queue row admits the proof edges of the queue span; the
// last workgroup commits the proofs and their edges (proof_commit_audit.slang).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID, uint3 ltid : SV_GroupThreadID)
{
    if (trait_solver_params.phase != 59u || proof_store_params.phase != 59u) return;
    pps_stage_admit_proof_edge_rows(thread_id.x);
    if (!pca_last_group(ltid.x)) return;
    pca_reset_arrivals();
    pps_stage_commit_proofs();
}
