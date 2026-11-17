// Re-arm canonical interning after later producers added candidates: rows
// materialized or generated after the early pass, and constants published
// during inference. Every interned candidate keeps its reference; empty and
// unknown candidates are retried by the next rounds (round 0 skips the
// rest). The table, records and overflow bits are kept.
//
// A candidate that is still empty (a row without a kind, an atom without a
// value, a projection without an operand) gets CT_NONE here, the reference
// round 0 would publish for it (canonical_build_candidate_key), so round 0
// does not intern the millions of empty slots of the capacity-sized tables.
import type_checker.canonical.canonical_api;
import type_checker.constant_atoms;

StructuredBuffer<uint> type_instance_kind;

bool candidate_empty(uint candidate, uint rows, uint atoms)
{
    if (candidate < rows)
    {
        uint count; uint stride;
        type_instance_kind.GetDimensions(count, stride);
        return candidate >= count || type_instance_kind[candidate] == 0u;
    }
    uint3 value; uint target; uint2 child;
    if (candidate - rows < atoms) return !checked_constant_atom_value(candidate - rows, value);
    return !checked_constant_projection(candidate - rows - atoms, target, child);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint count = ct_candidate_count();
    if (i < count)
    {
        uint state = ct_candidate_state(i);
        bool rearm_interned = ct_counts[CT_COUNT_EARLY_REARM] != 0u;
        bool interned = ct_is_resolved(state);
        // A candidate still pending from the job's clear is re-armed as well.
        if (state == CT_PENDING || state == CT_NONE || state == CT_UNKNOWN || (rearm_interned && interned))
        {
            uint rows = ct_row_capacity();
            uint atoms = ct_atom_capacity();
            uint next = candidate_empty(i, rows, atoms) ? CT_NONE : CT_PENDING;
            if (next != state)
            {
                if (i < rows) canonical_row[i] = next;
                else if (i - rows < atoms) canonical_atom[i - rows] = next;
                else canonical_projection[i - rows - atoms] = next;
            }
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
