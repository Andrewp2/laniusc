// Re-arm canonical interning after later producers added candidates: rows
// materialized or generated after the early pass, and constants published
// during inference. Every interned candidate keeps its reference; empty and
// unknown candidates are retried by the next rounds (round 0 skips the
// rest). The table, records and overflow bits are kept.
//
// A body replay (body_specialization_inputs) rewrites rows and constants
// that the early stage interned, so its late stage re-arms every candidate
// and sets CT_COUNT_REINTERN: keys are looked up first, and a rewritten
// candidate never overwrites the record of its earlier key
// (canonical_candidates.slang). The early stage of a replay finds nothing
// interned and leaves the flag clear.
import type_checker.canonical.canonical_api;

// Header (argument count, ...); [705].x is the constant binding count and
// [705].y the extra batched entries. A replay has at least one argument in
// one of the two domains.
StructuredBuffer<uint4> body_specialization_inputs;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint count = ct_candidate_count();
    if (i < count)
    {
        uint state = ct_candidate_state(i);
        bool replay = body_specialization_inputs[0u].x != 0u || body_specialization_inputs[705u].x != 0u ||
            body_specialization_inputs[705u].y != 0u;
        bool interned = ct_is_resolved(state);
        if (state == CT_NONE || state == CT_UNKNOWN || (replay && interned))
        {
            uint rows = ct_row_capacity();
            uint atoms = ct_atom_capacity();
            if (i < rows) canonical_row[i] = CT_PENDING;
            else if (i - rows < atoms) canonical_atom[i - rows] = CT_PENDING;
            else canonical_projection[i - rows - atoms] = CT_PENDING;
            // Set only here; 00_clear clears it for the next job.
            if (interned) ct_counts[CT_COUNT_REINTERN] = 1u;
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
