import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.catalog_admission.catalog_admission_dispatch;
import type_checker.trait_solver.catalog_admission.catalog_row_admission;
import shared.buffers.gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 2u || dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (!ts_catalog_is_building() || ts_publish_implementation_fault(local)) return;
    uint row;
    if (!ts_catalog_admission_row(10u, local, row)) return;
    SolverStatus status = ts_admit_catalog_method(row);
    ts_catalog_failure(status);
}
