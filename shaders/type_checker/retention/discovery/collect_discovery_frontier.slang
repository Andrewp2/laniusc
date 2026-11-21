import type_checker.retention.discovery.discovery_admission;
import type_checker.retention.discovery.discovery_frontier;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.collect_retained_requests_program;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint lane = dg_lane(id);
    if (lane == 0u && dg_proof_identity[0u] != 0u && !dg_proofs_current())
        dg_status[10u] = 8u;

    if (dg_config[4u] != 0u)
    {
        if (lane < rt_counts[RT_A_USES] &&
            (dg_config[10u] == 0u || (dg_receipt[0u] == 1u && dg_receipt[1u] == 0u)))
            collect_root_request(lane);
    }
    else
    {
        DiscoveryFrontier frontier = discovery_frontier();
        if (lane < frontier.hi - frontier.lo) collect_instance_requests(frontier.lo + lane);
    }
}
