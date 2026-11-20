import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_term_counts;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint term = RT_FIRST_TERM + dg_lane(id);
    if (term < rt_counts[RT_A_TERMS]) count_discovered_term(term, dg_config[0] == 0u);
}
