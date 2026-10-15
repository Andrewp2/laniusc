import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_substitution_walk;
import type_checker.program_evidence.proof_frontier_stages;

// Substitution walk up to the head match: proof work admission (phase 54)
// or implementation proof admission (phase 59).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    uint phase = proof_store_params.phase;
    if (program_evidence_params.phase != phase ||
        (phase != PPS_WALK_PHASE_WORK && phase != PPS_WALK_PHASE_PROOFS)) return;
    pps_stage_walk_goals(thread_id.x, phase);
}
