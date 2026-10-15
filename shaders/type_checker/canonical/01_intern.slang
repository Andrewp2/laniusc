// One interning round (docs/canonical-type-ids.md, "Rounds"). Round 0 is a
// direct dispatch over every candidate; later rounds are indirect over the
// frontier of candidates whose children were still pending. Each candidate
// is interned by its own lane in one pass, and no lane waits for another.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_checked_rows;

// Two frontier lists of half the buffer each; round r reads list r & 1 and
// appends to list (r + 1) & 1. The lists are sized from a fraction of the
// candidates (canonical_passes.rs): an append past the end sets
// CT_OVERFLOW_FRONTIER, and the host records the job again with larger lists.
RWStructuredBuffer<uint> canonical_frontier;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint round = ct_counts[CT_COUNT_ROUND];
    uint count = ct_candidate_count();
    uint words; uint stride;
    canonical_frontier.GetDimensions(words, stride);
    uint list = words / 2u;
    uint candidate;
    if (round == 0u)
    {
        // The early 03_rearm has read the flag; the late one must not.
        if (i == 0u) ct_counts[CT_COUNT_EARLY_REARM] = 0u;
        if (i >= count) return;
        // Constants first, then rows from the last: within one dispatch the
        // leaves then tend to publish before the rows that read them.
        uint constants = count - ct_row_capacity();
        candidate = i < constants ? count - constants + i : count - 1u - i;
        // A re-armed job keeps every candidate interned earlier.
        if (ct_candidate_state(candidate) != CT_PENDING) return;
    }
    else
    {
        // An overflowed round's count exceeds its list; the job is recorded
        // again, so its remaining rounds only stay in bounds.
        if (i >= min(ct_counts[CT_COUNT_PENDING], list)) return;
        candidate = canonical_frontier[(round & 1u) * list + i];
    }
    uint id = canonical_intern_candidate<CtCheckedRows>(candidate, ct_counts[CT_COUNT_FINAL] != 0u);
    if (id != CT_PENDING)
    {
        ct_publish_candidate(candidate, id);
        return;
    }
    uint next = (round + 1u) & 1u;
    uint slot;
    InterlockedAdd(ct_counts[CT_COUNT_FRONTIER + next], 1u, slot);
    if (slot < list) canonical_frontier[next * list + slot] = candidate;
    else InterlockedOr(ct_counts[CT_COUNT_OVERFLOW], CT_OVERFLOW_FRONTIER);
}
