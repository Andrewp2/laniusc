import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.catalog_index;

public void pev_catalog_initialize()
{
    // Host reset CatalogStatus to UNPROCESSED at a trusted output address first.
    // If the claimed layout itself is unsafe, leave that receipt unprocessed.
    EvidenceStatus layout = pev_admit_output_layout();
    if (layout.state != PEV_VALID) return;
    EvidenceStatus blank = pev_ok(); blank.state = PEV_CATALOG_BUILDING;
    pev_write_status(0u, 0u, blank);
    EvidenceStatus status = pev_admit_directories();
    if (status.state != PEV_VALID) pev_catalog_failure(status);
}
public void pev_catalog_clear_work(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint rows; uint buckets; uint row;
    if (!pev_work_counts(rows, buckets)) { pev_catalog_failure(pev_invalid(19u, 6u, PEV_INVALID)); return; }
    if (pev_dispatch_row(local, max(rows, buckets), row))
    {
        if (row < rows)
        {
            pev_output_write(6u, row, 0u, 0u); pev_output_write(6u, row, 1u, PEV_INVALID);
            pev_output_write(6u, row, 2u, PEV_INVALID); pev_output_write(6u, row, 3u, 0u);
        }
        if (row < buckets) pev_output_write(7u, row, 0u, PEV_INVALID);
    }
}
// Phase8 preserves atom-map scratch reuse: exact6/7 is cleared only after
// duplicate identities and method targets have consumed it. The additional
// coarse11/12 index has an independent immutable lifetime after this rebuild.
public void pev_catalog_clear_implementation_indexes(uint local)
{
    pev_catalog_clear_work(local);
    if (!pev_catalog_is_building()) return;
    uint implementations; uint rows; uint buckets; uint row;
    if (!pev_catalog_count(9u, implementations) || !pev_work_counts(rows, buckets))
    { pev_catalog_failure(pev_invalid(19u, 11u, PEV_INVALID)); return; }
    if (!pev_dispatch_row(local, max(implementations, buckets), row)) return;
    if (row < implementations &&
        (!pev_output_write(11u, row, 0u, 0u) || !pev_output_write(11u, row, 1u, PEV_INVALID) ||
         !pev_output_write(11u, row, 2u, PEV_INVALID) || !pev_output_write(11u, row, 3u, 0u)))
    { pev_catalog_failure(pev_invalid(1u, row, 11u)); return; }
    if (row < buckets && !pev_output_write(12u, row, 0u, PEV_INVALID))
        pev_catalog_failure(pev_invalid(1u, row, 12u));
}

public void pev_catalog_build_atoms(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint atoms; uint row;
    if (!pev_catalog_count(1u, atoms) || !pev_dispatch_row(local, atoms, row)) return;
    pev_publish_index(row, pev_atom_hash(row), PEV_INVALID);
}
public void pev_catalog_check_atoms(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint atoms; uint row;
    if (!pev_catalog_count(1u, atoms) || !pev_dispatch_row(local, atoms, row)) return;
    pev_catalog_failure(pev_check_atom_unique(row));
}
public void pev_catalog_map_callables(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint callables; uint row;
    if (!pev_catalog_count(4u, callables) || !pev_dispatch_row(local, callables, row)) return;
    uint atom; uint atoms; uint arena; uint address;
    if (!pev_word(4u, row, 0u, atom) || !pev_catalog_count(1u, atoms) || atom >= atoms ||
        !pev_output_address(6u, atom, 2u, arena, address) || arena != 0u)
    { pev_catalog_failure(pev_invalid(14u, row, PEV_INVALID)); return; }
    uint previous;
    InterlockedCompareExchange(program_evidence_catalog[address], PEV_INVALID, row, previous);
    if (previous != PEV_INVALID) pev_catalog_failure(pev_invalid(16u, row, previous));
}
public void pev_catalog_map_definition_identities(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint owners; uint predicates; uint implementations; uint row;
    if (!pev_catalog_count(2u, owners) || !pev_catalog_count(8u, predicates) ||
        !pev_catalog_count(9u, implementations) ||
        !pev_dispatch_row(local, max(owners, max(predicates, implementations)), row)) return;
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
        if (!pev_word(table, row, 0u, atom) || !pev_catalog_count(1u, atoms) || atom >= atoms ||
            !pev_output_address(6u, atom, 2u, arena, address) || arena != 0u)
        { pev_catalog_failure(pev_invalid(16u, row, PEV_INVALID)); return; }
        uint previous;
        InterlockedCompareExchange(program_evidence_catalog[address], PEV_INVALID, row, previous);
        if (previous != PEV_INVALID) { pev_catalog_failure(pev_invalid(16u, row, previous)); return; }
    }
}
public void pev_catalog_check_method_targets(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint methods; uint row;
    if (!pev_catalog_count(10u, methods) || !pev_dispatch_row(local, methods, row)) return;
    uint atom; uint owner; uint atoms; uint callable = PEV_INVALID; uint4 target;
    if (!pev_word(10u, row, 2u, atom) || !pev_word(10u, row, 4u, owner) ||
        !pev_catalog_count(1u, atoms) || atom >= atoms || !pev_output_read(6u, atom, 2u, callable) ||
        callable == PEV_INVALID || !pev_read4(4u, callable, 0u, target) ||
        target.x != atom || target.y != owner)
        pev_catalog_failure(pev_invalid(14u, row, callable));
}
public void pev_catalog_build_implementations(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint implementations; uint row;
    if (!pev_catalog_count(9u, implementations) || !pev_dispatch_row(local, implementations, row)) return;
    uint admitted; uint coarse_hash = 0u; uint exact_hash = 0u; bool exact = false;
    EvidenceStatus status;
    if (!pev_output_read(1u, row, 0u, admitted) || admitted != PEV_VALID)
        status = pev_invalid(15u, row, PEV_INVALID);
    else
    {
        if (pev_bind_scratch(local, row, status)) status = pev_hash_coarse_implementation(row, coarse_hash);
        if (status.state == PEV_VALID) status = pev_exact_implementation_eligible(row, exact);
        if (status.state == PEV_VALID && exact) status = pev_hash_admitted_implementation(row, exact_hash);
        if (status.state != PEV_VALID) pev_write_status(1u, row, status);
    }
    // All definitions participate in coarse selection/coherence. Only closed,
    // unconditional definitions enter the existing exact fast path. Each
    // publication, or the failure above, is reported in order at one site.
    uint publications = status.state != PEV_VALID ? 0u : exact ? 2u : 1u;
    [loop]
    for (uint index = 0u; ; index++)
    {
        if (index < publications)
            status = pev_publish_implementation_index(row, index, index == 0u ? coarse_hash : exact_hash);
        pev_catalog_failure(status);
        if (index + 1u >= max(publications, 1u)) return;
    }
}
public void pev_catalog_check_coherence(uint local)
{
    if (!pev_catalog_is_building()) return;
    uint implementations; uint row;
    if (!pev_catalog_count(9u, implementations) || !pev_dispatch_row(local, implementations, row)) return;
    EvidenceStatus status;
    if (pev_bind_scratch(local, row, status)) status = pev_check_impl_coherence(row);
    pev_write_status(1u, row, status);
    pev_catalog_failure(status);
}
public void pev_catalog_freeze()
{
    // Host calls only after every required phase and barrier, including clear
    // for zero implementations. No native gate observes provisional success.
    if (!pev_catalog_is_building()) return;
    uint arena; uint address;
    if (!pev_output_address(0u, 0u, 0u, arena, address) || arena != 0u) return;
    uint previous;
    InterlockedCompareExchange(program_evidence_catalog[address], PEV_CATALOG_BUILDING, PEV_VALID, previous);
}
