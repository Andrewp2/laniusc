import type_checker.retention.discovery.discovery_workspace;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    // Preserve the closed-term height check without sorting the term arena.
    uint term = RT_FIRST_TERM + dg_lane(id);
    if (term >= rt_counts[RT_A_TERMS] || rt_term_head[term].x == 0u || !rt_term_closed(term))
        return;
    uint height = rt_term_height(term);
    if (height == 0u || height >= 128u) dg_status[10u] = 8u;
}
