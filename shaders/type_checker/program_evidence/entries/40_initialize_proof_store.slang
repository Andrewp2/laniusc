import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_store_lifecycle;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 40u || proof_store_params.phase != 40u) return;
    if (any(dtid != uint3(0u, 0u, 0u)) ||
        program_evidence_params.dispatch_first != 0u || program_evidence_params.dispatch_count != 1u) return;
    pps_store_failure(pps_initialize_store());
}
