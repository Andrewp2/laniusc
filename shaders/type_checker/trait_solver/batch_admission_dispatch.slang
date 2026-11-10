// Typed batch entry dispatch. Keep phase/range/suffix authorization here so
// each entry reaches only its own existing row validator.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.batch_row_admission;

public bool ts_batch_admission_row(uint table, uint local, out uint row)
{
    row = TS_INVALID;
    if (!ts_batch_is_building()) return false;
    uint count; EvidenceStatus failure = ts_ok();
    if (!ts_table_count(table, count)) failure = ts_invalid(1u, table, TS_INVALID);
    else
    {
        if (!ts_dispatch_row(local, count, row)) return false;
        // Preserve the generic dispatcher's reverse prefix/suffix membership gate.
        if (!ts_batch_row(table, row)) failure = ts_invalid(1u, row, table);
    }
    if (failure.state == TS_VALID) return true;
    ts_batch_failure(failure);
    return false;
}

// These are the reference-row and Env11 invocation projections previously in
// the generic table switch. Every other entry calls its existing validator.
public EvidenceStatus ts_admit_batch_reference_row(uint table, uint row)
{
    // Atom1 and Node5 admission completed before these stages. Validate
    // each edge/root's own reference domain/bounds, including orphan rows.
    uint2 reference;
    if (!ts_read2(table, row, 0u, reference) ||
        !(ts_admitted_type_reference_shape(reference) || ts_admitted_constant_reference_shape(reference)))
        return ts_invalid(4u, row, table);
    return ts_ok();
}
public EvidenceStatus ts_admit_batch_environment_row(uint row)
{
    uint form; uint owner;
    if (!ts_word(11u, row, 3u, form) || !ts_word(11u, row, 4u, owner))
        return ts_invalid(1u, row, 11u);
    return ts_admit_batch_environment(row, form, owner);
}
