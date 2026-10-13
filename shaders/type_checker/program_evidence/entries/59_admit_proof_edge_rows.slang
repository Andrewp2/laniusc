import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_frontier_stages;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 59u || proof_store_params.phase != 59u) return;
    pps_stage_admit_proof_edge_rows(thread_id.x);
}
