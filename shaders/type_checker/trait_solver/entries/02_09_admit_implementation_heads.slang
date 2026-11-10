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
    SolverStatus status;
    if (ts_bind_scratch(local, row, status)) status = ts_admit_catalog_implementation_head(row);
    // A passing head is reported by 02_09_admit_implementation_members, which
    // runs only while every implementation head has passed.
    if (status.state != TS_VALID) ts_write_status(1u, row, status);
    ts_catalog_failure(status);
}
