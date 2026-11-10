import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.catalog_admission_dispatch;
import type_checker.trait_solver.catalog_row_admission;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 2u || dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint row;
    if (!ts_catalog_admission_row(9u, local, row)) return;
    EvidenceStatus status;
    // Every head passed: a failed head stops the catalog building.
    if (ts_bind_scratch(local, row, status)) status = ts_admit_catalog_implementation_members(row);
    ts_write_status(1u, row, status);
    ts_catalog_failure(status);
}
