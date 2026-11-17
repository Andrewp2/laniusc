// Re-arm canonical interning in place (canonical_rearm.slang). Used where
// passes intern what they read on demand, with no rounds after it (the body
// specialization). The stages' rounds start from 03a_rearm_list.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_rearm;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    // After the early stage: only the allocated candidates.
    LiveRearm live = canonical_live_rearm();
    if (i < canonical_live_rearm_count(live))
        canonical_rearm_candidate(canonical_live_rearm_candidate(live, i));
    if (i == 0u) canonical_rearm_reset_rounds();
}
