// Re-arm the candidates interned ahead of the early canonical stage. The
// imported alias targets (dependencies/14a, 08) intern their leaf rows on
// demand, and alias normalization then rewrites those rows, so every
// resolved candidate goes back to pending and the early stage interns it
// again: an unchanged key adopts its existing record, a rewritten one gets
// its own. Runs once, after the last realization dispatch; a job that
// interned nothing early leaves every candidate as it is.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (i >= ct_candidate_count() || ct_subst_counts[CT_SUBST_COUNT_EARLY_INTERNED] == 0u) return;
    if (!ct_is_resolved(ct_candidate_state(i))) return;
    uint rows = ct_row_capacity();
    uint atoms = ct_atom_capacity();
    if (i < rows) canonical_row[i] = CT_PENDING;
    else if (i - rows < atoms) canonical_atom[i - rows] = CT_PENDING;
    else canonical_projection[i - rows - atoms] = CT_PENDING;
}
