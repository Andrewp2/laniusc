import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_normalization_stages;

// One workgroup: the lanes audit together, then lane 0 publishes, or runs the
// serial stage when the group audit does not prove success.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group : SV_GroupID, uint lane : SV_GroupIndex)
{
    if (program_evidence_params.phase != 45u || proof_store_params.phase != 45u) return;
    if (any(group != uint3(0u, 0u, 0u)) ||
        program_evidence_params.dispatch_first != 0u || program_evidence_params.dispatch_count != 1u) return;
    if (!pps_building() || !pev_batch_is_building()) return;
    bool audited = pps_group_audit_normalized_terms(lane);
    if (lane != 0u) return;
    pev_batch_failure(audited ? pps_publish_normalized_terms() : pps_commit_normalized_terms());
}
