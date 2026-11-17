// Re-arming one interning candidate after later producers added candidates
// (docs/canonical-type-ids.md, "Stages"): rows materialized or generated
// after the early pass, and constants published during inference. Every
// interned candidate keeps its reference; pending, empty and unknown
// candidates are retried (and every interned one when CT_COUNT_EARLY_REARM
// is set). The table, records and overflow bits are kept.
//
// A candidate that is still empty (a row without a kind, an atom without a
// value, a projection without an operand) gets CT_NONE here, the reference
// interning would publish for it (canonical_build_candidate_key), so the
// rounds do not intern the millions of empty slots of the capacity-sized
// tables.
import type_checker.canonical.canonical_api;
import type_checker.constant_atoms;

public StructuredBuffer<uint> type_instance_kind;

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

// Re-arms `candidate` (below ct_candidate_count()). True when it is left
// pending for the rounds.
public bool canonical_rearm_candidate(uint candidate)
{
    uint state = ct_candidate_state(candidate);
    bool rearm_interned = ct_counts[CT_COUNT_EARLY_REARM] != 0u;
    if (state != CT_PENDING && state != CT_NONE && state != CT_UNKNOWN &&
        !(rearm_interned && ct_is_resolved(state))) return false;
    uint rows = ct_row_capacity();
    uint atoms = ct_atom_capacity();
    uint next = candidate_empty(candidate, rows, atoms) ? CT_NONE : CT_PENDING;
    if (next != state)
    {
        if (candidate < rows) canonical_row[candidate] = next;
        else if (candidate - rows < atoms) canonical_atom[candidate - rows] = next;
        else canonical_projection[candidate - rows - atoms] = next;
    }
    return next == CT_PENDING;
}

// Resets the round state for the rounds that follow (one lane).
public void canonical_rearm_reset_rounds()
{
    ct_counts[CT_COUNT_PENDING] = ct_candidate_count();
    ct_counts[CT_COUNT_ROUND] = 0u;
    ct_counts[CT_COUNT_FRONTIER] = 0u;
    ct_counts[CT_COUNT_FRONTIER + 1u] = 0u;
    ct_counts[CT_COUNT_FINAL] = 0u;
}
