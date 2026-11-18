// Re-arm canonical interning for a stage's rounds (canonical_rearm.slang)
// and list the candidates left pending: round 0 of intern_canonical_types interns only
// those (canonical_pending, counted in CT_COUNT_REARM_PENDING; write_canonical_rearm_dispatch_args turns the
// count into round 0's dispatch).
//
// The list keeps the order round 0 swept the candidates in: constants
// first, then rows from the last, so leaves tend to publish before the rows
// that read them.
import type_checker.canonicalization.canonical_api;
import type_checker.canonicalization.canonical_rearm;

RWStructuredBuffer<uint> canonical_pending;

#include "rearm_list_append.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint count = ct_candidate_count();
    LiveRearm live = canonical_live_rearm();
    uint constants = count - ct_row_capacity();
    // The lanes of a wave step together, so each step appends with one
    // atomic per wave.
    for (uint first = lane - WaveGetLaneIndex(); first < count; first += CANONICAL_REARM_LANES)
    {
        uint i = first + WaveGetLaneIndex();
        uint candidate = 0u;
        bool pending = false;
        if (i < count)
        {
            candidate = i < constants ? count - constants + i : count - 1u - i;
            // Past the allocation counters a candidate is empty
            // (canonical_live_rearm): it gets CT_NONE without reading it.
            pending = canonical_rearm_candidate(candidate, canonical_live_rearm_holds(live, candidate));
        }
        rearm_list_append(candidate, pending);
    }
    if (lane == 0u) canonical_rearm_reset_rounds();
}
