// The re-arm list of the stages after the early one: list_canonical_candidates_to_rearm over
// the allocated candidates only (canonical_live_rearm), in the same order.
import type_checker.canonicalization.canonical_api;
import type_checker.canonicalization.canonical_rearm;

RWStructuredBuffer<uint> canonical_pending;

#include "rearm_list_append.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    LiveRearm live = canonical_live_rearm();
    uint count = canonical_live_rearm_count(live);
    // The lanes of a wave step together, so each step appends with one
    // atomic per wave.
    for (uint first = lane - WaveGetLaneIndex(); first < count; first += CANONICAL_REARM_LANES)
    {
        uint i = first + WaveGetLaneIndex();
        uint candidate = 0u;
        bool pending = false;
        if (i < count)
        {
            candidate = canonical_live_rearm_candidate(live, i);
            pending = canonical_rearm_candidate(candidate);
        }
        rearm_list_append(candidate, pending);
    }
    if (lane == 0u) canonical_rearm_reset_rounds();
}
