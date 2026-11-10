import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.catalog_index;

public void ts_catalog_initialize()
{
    // Host reset CatalogStatus to UNPROCESSED at a trusted output address first.
    // If the claimed layout itself is unsafe, leave that receipt unprocessed.
    EvidenceStatus layout = ts_admit_output_layout();
    if (layout.state != TS_VALID) return;
    EvidenceStatus blank = ts_ok(); blank.state = TS_CATALOG_BUILDING;
    ts_write_status(0u, 0u, blank);
    EvidenceStatus status = ts_admit_directories();
    if (status.state != TS_VALID) ts_catalog_failure(status);
}
public void ts_catalog_clear_work(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint rows; uint buckets; uint row;
    if (!ts_work_counts(rows, buckets)) { ts_catalog_failure(ts_invalid(19u, 6u, TS_INVALID)); return; }
    if (ts_dispatch_row(local, max(rows, buckets), row))
    {
        if (row < rows)
        {
            ts_output_write(6u, row, 0u, 0u); ts_output_write(6u, row, 1u, TS_INVALID);
            ts_output_write(6u, row, 2u, TS_INVALID); ts_output_write(6u, row, 3u, 0u);
        }
        if (row < buckets) ts_output_write(7u, row, 0u, TS_INVALID);
    }
}
// Phase8 preserves atom-map scratch reuse: exact6/7 is cleared only after
// duplicate identities and method targets have consumed it. The additional
// coarse11/12 index has an independent immutable lifetime after this rebuild.
public void ts_catalog_clear_implementation_indexes(uint local)
{
    ts_catalog_clear_work(local);
    if (!ts_catalog_is_building()) return;
    uint implementations; uint rows; uint buckets; uint row;
    if (!ts_catalog_count(9u, implementations) || !ts_work_counts(rows, buckets))
    { ts_catalog_failure(ts_invalid(19u, 11u, TS_INVALID)); return; }
    if (!ts_dispatch_row(local, max(implementations, buckets), row)) return;
    if (row < implementations &&
        (!ts_output_write(11u, row, 0u, 0u) || !ts_output_write(11u, row, 1u, TS_INVALID) ||
         !ts_output_write(11u, row, 2u, TS_INVALID) || !ts_output_write(11u, row, 3u, 0u)))
    { ts_catalog_failure(ts_invalid(1u, row, 11u)); return; }
    if (row < buckets && !ts_output_write(12u, row, 0u, TS_INVALID))
        ts_catalog_failure(ts_invalid(1u, row, 12u));
}

public void ts_catalog_build_atoms(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint atoms; uint row;
    if (!ts_catalog_count(1u, atoms) || !ts_dispatch_row(local, atoms, row)) return;
    ts_publish_index(row, ts_atom_hash(row), TS_INVALID);
}
public void ts_catalog_check_atoms(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint atoms; uint row;
    if (!ts_catalog_count(1u, atoms) || !ts_dispatch_row(local, atoms, row)) return;
    ts_catalog_failure(ts_check_atom_unique(row));
}
public void ts_catalog_map_callables(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint callables; uint row;
    if (!ts_catalog_count(4u, callables) || !ts_dispatch_row(local, callables, row)) return;
    uint atom; uint atoms; uint arena; uint address;
    if (!ts_word(4u, row, 0u, atom) || !ts_catalog_count(1u, atoms) || atom >= atoms ||
        !ts_output_address(6u, atom, 2u, arena, address) || arena != 0u)
    { ts_catalog_failure(ts_invalid(14u, row, TS_INVALID)); return; }
    uint previous;
    InterlockedCompareExchange(trait_solver_catalog[address], TS_INVALID, row, previous);
    if (previous != TS_INVALID) ts_catalog_failure(ts_invalid(16u, row, previous));
}
public void ts_catalog_map_definition_identities(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint owners; uint predicates; uint implementations; uint row;
    if (!ts_catalog_count(2u, owners) || !ts_catalog_count(8u, predicates) ||
        !ts_catalog_count(9u, implementations) ||
        !ts_dispatch_row(local, max(owners, max(predicates, implementations)), row)) return;
    // Binder, predicate, implementation, and callable atoms have disjoint
    // admitted kinds. Each exact identity owns one authoritative definition row.
    // In particular, an implementation duplicate rejects even with a different
    // goal hash, and duplicate owner rows cannot split one binder's scope.
    for (uint kind = 0u; kind < 3u; kind++)
    {
        uint table = kind == 0u ? 2u : (kind == 1u ? 8u : 9u);
        uint count = kind == 0u ? owners : (kind == 1u ? predicates : implementations);
        if (row >= count) continue;
        uint atom; uint atoms; uint arena; uint address;
        if (!ts_word(table, row, 0u, atom) || !ts_catalog_count(1u, atoms) || atom >= atoms ||
            !ts_output_address(6u, atom, 2u, arena, address) || arena != 0u)
        { ts_catalog_failure(ts_invalid(16u, row, TS_INVALID)); return; }
        uint previous;
        InterlockedCompareExchange(trait_solver_catalog[address], TS_INVALID, row, previous);
        if (previous != TS_INVALID) { ts_catalog_failure(ts_invalid(16u, row, previous)); return; }
    }
}
public void ts_catalog_check_method_targets(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint methods; uint row;
    if (!ts_catalog_count(10u, methods) || !ts_dispatch_row(local, methods, row)) return;
    uint atom; uint owner; uint atoms; uint callable = TS_INVALID; uint4 target;
    if (!ts_word(10u, row, 2u, atom) || !ts_word(10u, row, 4u, owner) ||
        !ts_catalog_count(1u, atoms) || atom >= atoms || !ts_output_read(6u, atom, 2u, callable) ||
        callable == TS_INVALID || !ts_read4(4u, callable, 0u, target) ||
        target.x != atom || target.y != owner)
        ts_catalog_failure(ts_invalid(14u, row, callable));
}
public void ts_catalog_build_implementations(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint implementations; uint row;
    if (!ts_catalog_count(9u, implementations) || !ts_dispatch_row(local, implementations, row)) return;
    uint admitted; uint coarse_hash = 0u; uint exact_hash = 0u; bool exact = false;
    EvidenceStatus status;
    if (!ts_output_read(1u, row, 0u, admitted) || admitted != TS_VALID)
        status = ts_invalid(15u, row, TS_INVALID);
    else
    {
        if (ts_bind_scratch(local, row, status)) status = ts_hash_coarse_implementation(row, coarse_hash);
        if (status.state == TS_VALID) status = ts_exact_implementation_eligible(row, exact);
        if (status.state == TS_VALID && exact) status = ts_hash_admitted_implementation(row, exact_hash);
        if (status.state != TS_VALID) ts_write_status(1u, row, status);
    }
    // All definitions participate in coarse selection/coherence. Only closed,
    // unconditional definitions enter the existing exact fast path. Each
    // publication, or the failure above, is reported in order at one site.
    uint publications = status.state != TS_VALID ? 0u : exact ? 2u : 1u;
    [loop]
    for (uint index = 0u; ; index++)
    {
        if (index < publications)
            status = ts_publish_implementation_index(row, index, index == 0u ? coarse_hash : exact_hash);
        ts_catalog_failure(status);
        if (index + 1u >= max(publications, 1u)) return;
    }
}
public void ts_catalog_check_coherence(uint local)
{
    if (!ts_catalog_is_building()) return;
    uint implementations; uint row;
    if (!ts_catalog_count(9u, implementations) || !ts_dispatch_row(local, implementations, row)) return;
    EvidenceStatus status;
    if (ts_bind_scratch(local, row, status)) status = ts_check_impl_coherence(row);
    ts_write_status(1u, row, status);
    ts_catalog_failure(status);
}
public void ts_catalog_freeze()
{
    // Host calls only after every required phase and barrier, including clear
    // for zero implementations. No native gate observes provisional success.
    if (!ts_catalog_is_building()) return;
    uint arena; uint address;
    if (!ts_output_address(0u, 0u, 0u, arena, address) || arena != 0u) return;
    uint previous;
    InterlockedCompareExchange(trait_solver_catalog[address], TS_CATALOG_BUILDING, TS_VALID, previous);
}
