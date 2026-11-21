import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.batches.batch_row_admission;
import shared.buffers.gpu_index;

// Calls and contexts admitted their predicate contents. Check that each
// predicate belongs to its claimed parent, including rows outside all spans.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 46u || dtid.z != 0u || !ts_batch_is_building()) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint assumptions; uint obligations;
    if (!ts_table_count(14u, assumptions) || !ts_table_count(16u, obligations) ||
        obligations > TS_INVALID - assumptions)
    {
        ts_batch_failure(ts_invalid(1u, 14u, 16u));
        return;
    }
    uint row;
    if (!ts_dispatch_row(local, assumptions + obligations, row)) return;
    SolverStatus status = row < assumptions ? ts_admit_batch_assumption(row) :
        ts_admit_batch_obligation(row - assumptions);
    ts_batch_failure(status);
}
