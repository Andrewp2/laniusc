// Counts the rows phase 42 will reserve for the prerequisite Works just
// admitted (proof_demand.slang).
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_normalization_stages;
import type_checker.trait_solver.proof_demand;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 68u || proof_store_params.phase != 68u) return;
    if (dtid.z != 0u || !pps_building() || !ts_batch_is_building()) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count; uint row;
    if (!pps_count(PPS_WORK, count) || !ts_dispatch_row(local, count, row)) return;
    SolverStatus status; uint nodes; uint edges; uint roots;
    if (!ts_bind_scratch(local, row, status)) return;
    if (pps_measure_prerequisite_work(row, nodes, edges, roots))
        pps_add_normalization_demand(nodes, edges, roots);
}
