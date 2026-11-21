// Re-arm canonical interning in place (canonical_rearm.slang). Used where
// passes intern what they read on demand, with no rounds after it (the body
// specialization). The stages' rounds start from list_canonical_candidates_to_rearm.
import type_checker.canonicalization.canonical_api;
import type_checker.canonicalization.canonical_rearm;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    // After the early stage: only the allocated candidates.
    LiveRearm live = canonical_live_rearm();
    uint count = canonical_live_rearm_count(live);
    for (uint i = lane; i < count; i += CANONICAL_REARM_LANES)
        canonical_rearm_candidate(live, canonical_live_rearm_candidate(live, i));
    if (lane == 0u) canonical_rearm_reset_rounds(live);
}
