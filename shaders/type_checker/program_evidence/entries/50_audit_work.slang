import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_frontier_stages;
import gpu_index;

// One lane per pending Work row.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 50u || proof_store_params.phase != 50u) return;
    if (dtid.z != 0u) return;
    pps_stage_audit_work(linear_dispatch_thread_id_2d(dtid, 16776960u));
}
