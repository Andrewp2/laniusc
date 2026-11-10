// Shared dispatch guards only. Each phase02 entry calls its table's typed
// admission helper directly, so unrelated admission bodies are not reachable.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;

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
