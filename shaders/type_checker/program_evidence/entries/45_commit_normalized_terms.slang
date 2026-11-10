import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_normalization_stages;

// One thread, after 45_audit_normalized_terms.
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 45u || proof_store_params.phase != 45u) return;
    if (any(thread_id != uint3(0u, 0u, 0u))) return;
    pps_stage_commit_normalized_terms();
}
