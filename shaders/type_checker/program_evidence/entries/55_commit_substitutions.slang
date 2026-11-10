import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_frontier_stages;

// One thread, after 55_audit_substitutions.
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 55u || proof_store_params.phase != 55u) return;
    if (any(thread_id != uint3(0u, 0u, 0u))) return;
    pps_stage_commit_substitutions();
}
