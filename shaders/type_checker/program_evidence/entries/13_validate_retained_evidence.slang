// Draft only; no compilation or dispatch has been performed.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_stages;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 13u) return;
    if (dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    pev_batch_validate_evidence(local);
}
