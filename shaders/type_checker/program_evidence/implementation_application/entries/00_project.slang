import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.implementation_application.work_abi;
import type_checker.program_evidence.implementation_application.project;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 6u || proof_store_params.phase != 6u ||
        any(dtid != uint3(0u)) || program_evidence_params.dispatch_first != 0u ||
        program_evidence_params.dispatch_count != 1u || !iap_physical_work()) return;
    // A fresh exclusive arena starts with zero counters and an unpublished
    // receipt. No partial failure can publish a successful application list.
    EvidenceStatus status = pev_invalid(200u, PEV_INVALID, PEV_INVALID);
    if (iap_header_is_valid()) status = iap_project();
    iap_status(status);
}
