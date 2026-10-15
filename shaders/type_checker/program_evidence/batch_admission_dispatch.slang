// Typed batch entry dispatch. Keep phase/range/suffix authorization here so
// each entry reaches only its own existing row validator.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.batch_row_admission;

public bool pev_batch_admission_row(uint table, uint local, out uint row)
{
    row = PEV_INVALID;
    if (!pev_batch_is_building()) return false;
    uint count; EvidenceStatus failure = pev_ok();
    if (!pev_table_count(table, count)) failure = pev_invalid(1u, table, PEV_INVALID);
    else
    {
        if (!pev_dispatch_row(local, count, row)) return false;
        // Preserve the generic dispatcher's reverse prefix/suffix membership gate.
        if (!pev_batch_row(table, row)) failure = pev_invalid(1u, row, table);
    }
    if (failure.state == PEV_VALID) return true;
    pev_batch_failure(failure);
    return false;
}

// These are the reference-row and Env11 invocation projections previously in
// the generic table switch. Every other entry calls its existing validator.
public EvidenceStatus pev_admit_batch_reference_row(uint table, uint row)
{
    // Atom1 and Node5 admission completed before these stages. Validate
    // each edge/root's own reference domain/bounds, including orphan rows.
    uint2 reference;
    if (!pev_read2(table, row, 0u, reference) ||
        !(pev_admitted_type_reference_shape(reference) || pev_admitted_constant_reference_shape(reference)))
        return pev_invalid(4u, row, table);
    return pev_ok();
}
public EvidenceStatus pev_admit_batch_environment_row(uint row)
{
    uint form; uint owner;
    if (!pev_word(11u, row, 3u, form) || !pev_word(11u, row, 4u, owner))
        return pev_invalid(1u, row, 11u);
    return pev_admit_batch_environment(row, form, owner);
}
