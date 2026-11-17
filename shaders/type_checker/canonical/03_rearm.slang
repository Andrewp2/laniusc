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
    if (i < ct_candidate_count()) canonical_rearm_candidate(i);
    if (i == 0u) canonical_rearm_reset_rounds();
}
