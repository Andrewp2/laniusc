import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.collect_discovery_requests_step;

public RWStructuredBuffer<uint> dg_wave;

public DiscoveryFrontier discovery_frontier()
{
    return { dg_wave[0u], dg_wave[1u], dg_wave[2u] };
}

public void advance_discovery_frontier(uint wave, bool accept_predicates)
{
    uint lo = dg_wave[1];
    bool ready = (accept_predicates || dg_status[11] == dg_wave[3]) && dg_status[12] == 0u && dg_status[3] == 0u &&
        dg_status[10] == 0u && dg_status[6] == RT_INVALID;
    uint hi = ready ? max(lo, dg_status[0]) : lo;
    dg_wave[0] = lo;
    dg_wave[1] = hi;
    dg_wave[2] = dg_status[2];
    dg_wave[4u + 2u * wave] = lo;
    dg_wave[5u + 2u * wave] = hi;
}

