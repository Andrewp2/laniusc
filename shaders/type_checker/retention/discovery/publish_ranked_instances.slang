import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_publication;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (dg_status[30u] != 0u) return;
    uint row = dg_lane(id);
    if (row < max(rt_counts[RT_A_USES], max(dg_status[1u], dg_status[2u])))
        publish_discovered_instances(row, 1u);
    // Consumers run after the dispatch, once all rows are available.
    if (row == 0u) publish_discovered_instances(0u, 2u);
}
