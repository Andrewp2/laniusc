import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.implementation_application.work_abi;
import type_checker.trait_solver.implementation_application.project;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 6u || proof_store_params.phase != 6u ||
        any(dtid != uint3(0u)) || trait_solver_params.dispatch_first != 0u ||
        trait_solver_params.dispatch_count != 1u || !iap_physical_work()) return;
    // A fresh exclusive arena starts with zero counters and an unpublished
    // receipt. No partial failure can publish a successful application list.
    SolverStatus status = ts_invalid(200u, TS_INVALID, TS_INVALID);
    if (iap_header_is_valid()) status = iap_project();
    iap_status(status);
}
