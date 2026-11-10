import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_normalization_stages;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 44u || proof_store_params.phase != 44u) return;
    if (dtid.z != 0u || !pps_building() || !ts_batch_is_building()) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count; uint row;
    if (!pps_count(PPS_WORK, count))
    { ts_batch_failure(ts_invalid(1u, PPS_WORK, TS_INVALID)); return; }
    if (!ts_dispatch_row(local, count, row)) return;
    SolverStatus status;
    if (ts_bind_scratch(local, row, status)) status = pps_validate_prerequisite_work(row);
    ts_batch_failure(status);
}
