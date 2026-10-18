import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_normalization_stages;

// One workgroup over the one-row span (0, 1).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group : SV_GroupID, uint lane : SV_GroupIndex)
{
    if (program_evidence_params.phase != 47u || proof_store_params.phase != 47u) return;
    if (any(group != uint3(0u, 0u, 0u)) ||
        program_evidence_params.dispatch_first != 0u || program_evidence_params.dispatch_count != 1u) return;
    if (!pps_building() || !pev_batch_is_building()) return;
    pps_group_commit_normalized_goals(lane);
}
