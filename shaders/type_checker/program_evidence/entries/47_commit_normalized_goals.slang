import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_normalization_stages;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 47u || proof_store_params.phase != 47u) return;
    if (any(dtid != uint3(0u, 0u, 0u)) ||
        program_evidence_params.dispatch_first != 0u || program_evidence_params.dispatch_count != 1u) return;
    if (!pps_building() || !pev_batch_is_building()) return;
    pev_batch_failure(pps_commit_normalized_goals());
}
