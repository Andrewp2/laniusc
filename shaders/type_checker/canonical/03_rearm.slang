// Re-arm canonical interning after later producers added candidates: rows
// materialized or generated after the early pass, and constants published
// during inference. Every interned candidate keeps its reference; empty and
// unknown candidates are retried by the next rounds (round 0 skips the
// rest). The table, records and overflow bits are kept.
import type_checker.canonical.canonical_api;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint count = ct_candidate_count();
    if (i < count)
    {
        uint state = ct_candidate_state(i);
        if (state == CT_NONE || state == CT_UNKNOWN)
        {
            uint rows = ct_row_capacity();
            uint atoms = ct_atom_capacity();
            if (i < rows) canonical_row[i] = CT_PENDING;
            else if (i - rows < atoms) canonical_atom[i - rows] = CT_PENDING;
            else canonical_projection[i - rows - atoms] = CT_PENDING;
        }
    }
    if (i == 0u)
    {
        ct_counts[CT_COUNT_PENDING] = count;
        ct_counts[CT_COUNT_ROUND] = 0u;
        ct_counts[CT_COUNT_FRONTIER] = 0u;
        ct_counts[CT_COUNT_FRONTIER + 1u] = 0u;
        ct_counts[CT_COUNT_FINAL] = 0u;
    }
}
