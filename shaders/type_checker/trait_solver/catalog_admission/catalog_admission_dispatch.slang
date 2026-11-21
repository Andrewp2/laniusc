// The catalog row dispatch gate and implementation diagnostic publication.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_io;

public bool ts_catalog_admission_row(uint table, uint local, out uint row)
{
    row = TS_INVALID;
    if (!ts_catalog_is_building()) return false;
    uint count;
    if (!ts_catalog_count(table, count))
    {
        ts_catalog_failure(ts_invalid(1u, table, TS_INVALID)); return false;
    }
    return ts_dispatch_row(local, count, row);
}

// CatalogStatus word 7 is scratch while BUILDING. The complemented key
// orders faults by the old dispatch chunks, then head before members, then
// row. An admitted 12-word implementation table has fewer than 2^29 rows.
static const uint TS_IMPLEMENTATION_FAULT_KEY = 7u;
static const uint TS_IMPLEMENTATION_CHUNK_ROWS = 4096u;

public void ts_rank_implementation_fault(uint row, bool head_fault)
{
    uint arena; uint address;
    if (!ts_output_address(0u, 0u, TS_IMPLEMENTATION_FAULT_KEY, arena, address) || arena != 0u) return;
    uint within_chunk = row % TS_IMPLEMENTATION_CHUNK_ROWS;
    uint key = 2u * (row - within_chunk) + within_chunk +
        (head_fault ? 0u : TS_IMPLEMENTATION_CHUNK_ROWS);
    InterlockedMax(trait_solver_catalog[address], ~key);
}

// The method dispatch runs after all implementation lanes have published
// their statuses. Only its first lane can publish the winning diagnostic.
public bool ts_publish_implementation_fault(uint local)
{
    uint ranked;
    if (!ts_output_read(0u, 0u, TS_IMPLEMENTATION_FAULT_KEY, ranked) || ranked == 0u) return false;
    if (local == 0u && trait_solver_params.dispatch_first == 0u)
    {
        uint key = ~ranked;
        uint row = key / (2u * TS_IMPLEMENTATION_CHUNK_ROWS) * TS_IMPLEMENTATION_CHUNK_ROWS +
            key % TS_IMPLEMENTATION_CHUNK_ROWS;
        uint4 low; uint4 high;
        SolverStatus status = ts_invalid(1u, row, 1u);
        if (ts_output_read4(1u, row, 0u, low) && ts_output_read4(1u, row, 4u, high))
            status = ts_status(low.x, low.y, low.z, low.w, high.x, high.y);
        ts_catalog_failure(status);
    }
    return true;
}
