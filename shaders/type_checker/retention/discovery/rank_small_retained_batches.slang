import type_checker.retention.discovery.discovery_rank_order;
import type_checker.retention.discovery.discovery_workspace;

groupshared uint rank;

// Each workgroup computes one instance's position in canonical order.
// Bounded batches use pairwise comparisons to avoid serial sort steps.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    uint instance = group.x;
    uint count = dg_status[0u];
    if (instance >= count || dg_status[10u] != 0u) return;
    uint4 current = dg_instances[2u * instance];
    if (current.x == 0u) return;

    uint smaller = 0u;
    for (uint other = local.x; other < count; other += 256u)
    {
        uint4 candidate = dg_instances[2u * other];
        if (candidate.x == 0u) continue;
        int order = compare_instance_rows(candidate, current);
        if (order < 0 || (order == 0 && other < instance)) ++smaller;
    }
    if (local.x == 0u) rank = 0u;
    GroupMemoryBarrierWithGroupSync();
    uint sum = WaveActiveSum(smaller);
    if (WaveIsFirstLane()) InterlockedAdd(rank, sum);
    GroupMemoryBarrierWithGroupSync();
    if (local.x == 0u) dg_rank[instance] = rank;
}
