import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_frontier_stages;

// One workgroup over the one-row span (0, 1).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group : SV_GroupID, uint lane : SV_GroupIndex)
{
    if (program_evidence_params.phase != 55u || proof_store_params.phase != 55u) return;
    if (any(group != uint3(0u, 0u, 0u))) return;
    pps_stage_commit_substitutions_group(lane);
}
