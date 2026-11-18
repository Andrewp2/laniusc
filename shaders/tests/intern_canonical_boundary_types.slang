// Fixture setup for the canonical type boundary tests: intern the resident
// page's dependency nodes into the canonical table, as the per-page rounds
// (04_dependency_begin, 05_intern_dependency) do in a job. One lane visits
// the nodes in index order; children have smaller indices than parents, so
// every node resolves in one pass. The host clears ct_slot and sets every
// canonical_dependency_type entry to CT_PENDING.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import dependency_interface;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    for (uint i = 0u; i < CT_COUNT_WORDS; i++) ct_counts[i] = 0u;
    ct_counts[CT_COUNT_NEXT_RECORD] = CT_FIRST_RECORD;
    for (uint t = 0u; t < dependency_type_count(); t++)
    {
        uint id = canonical_intern_dependency(t, true);
        uint index = ct_dependency_index(t);
        if (index != 0xffffffffu) canonical_dependency_type[index] = id;
    }
}
