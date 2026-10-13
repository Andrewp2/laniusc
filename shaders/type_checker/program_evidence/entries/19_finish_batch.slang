// Draft only; no compilation or dispatch has been performed.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_stages;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 19u) return;
    if (any(dtid != uint3(0u, 0u, 0u)) ||
        program_evidence_params.dispatch_first != 0u || program_evidence_params.dispatch_count != 1u) return;
    pev_batch_finish();
}
