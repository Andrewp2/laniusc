import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_substitution_walk;
import type_checker.program_evidence.proof_frontier_stages;

// The head match of a substitution walk (phase 54 or 59), or the fixed
// prerequisite checks of an implementation proof after its walk (phase 66).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    uint phase = proof_store_params.phase;
    if (program_evidence_params.phase != phase ||
        (phase != PPS_WALK_PHASE_WORK && phase != PPS_WALK_PHASE_PROOFS &&
         phase != PPS_WALK_PHASE_PREREQUISITES)) return;
    pps_stage_walk_roots(thread_id.x, phase);
}
