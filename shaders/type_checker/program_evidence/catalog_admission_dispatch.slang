// Shared dispatch guards only. Each phase02 entry calls its table's typed
// admission helper directly, so unrelated admission bodies are not reachable.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;

public bool pev_catalog_admission_row(uint table, uint local, out uint row)
{
    row = PEV_INVALID;
    if (!pev_catalog_is_building()) return false;
    uint count;
    if (!pev_catalog_count(table, count))
    {
        pev_catalog_failure(pev_invalid(1u, table, PEV_INVALID)); return false;
    }
    return pev_dispatch_row(local, count, row);
}
