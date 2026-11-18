import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.batches.batch_admission_dispatch;
import type_checker.trait_solver.batches.batch_row_admission;
import gpu_index;

// The batch rows of the value graph in one dispatch: atoms (1), nodes (5),
// edges (6) and roots (7), lane by lane in that table order over each
// table's whole batch suffix (the host dispatches at least that many lanes).
// Each validator reads only its own row, so the four need no order.
SolverStatus admit_value_row(uint table, uint row)
{
    if (table == 1u) return ts_admit_batch_atom(row);
    if (table == 5u) return ts_admit_batch_node(row);
    return ts_admit_batch_reference_row(table, row);
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 33u || dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (local >= trait_solver_params.dispatch_count || !ts_batch_is_building()) return;
    [loop]
    for (uint i = 0u; i < 4u; i++)
    {
        uint table = i == 0u ? 1u : 4u + i;
        SolverTable desc;
        if (!ts_descriptor(table, desc)) { ts_batch_failure(ts_invalid(1u, table, TS_INVALID)); return; }
        if (local < desc.batch_count)
        {
            uint row = desc.catalog_count + local;
            ts_batch_failure(ts_batch_row(table, row) ? admit_value_row(table, row) : ts_invalid(1u, row, table));
            return;
        }
        local -= desc.batch_count;
    }
}
