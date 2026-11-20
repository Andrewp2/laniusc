import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_store_lifecycle;
import type_checker.trait_solver.proof_frontier.proof_work;
import type_checker.trait_solver.proof_frontier.proof_selection;

// One lane per source obligation of the batch, after every Work ran. Lane i
// publishes obligation dispatch_first + i from root Work i.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 86u || proof_store_params.phase != 86u) return;
    uint obligations; uint obligation;
    if (!pps_building() || !ts_batch_is_building() || !ts_table_count(16u, obligations) ||
        !ts_dispatch_row(thread_id.x, obligations, obligation)) return;
    pps_store_failure(pps_publish_root(obligation, thread_id.x));
}
