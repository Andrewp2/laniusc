import type_checker.trait_solver.abi;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.batch_admission_dispatch;
import type_checker.trait_solver.batch_row_admission;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 44u || dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint row;
    if (!ts_batch_admission_row(12u, local, row)) return;
    ts_batch_failure(ts_admit_batch_binding(row));
}
