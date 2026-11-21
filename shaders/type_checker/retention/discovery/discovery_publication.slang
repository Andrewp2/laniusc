import type_checker.retention.discovery.discovery_admission;
RWStructuredBuffer<uint4> pj_instances;
RWStructuredBuffer<uint4> pj_routes;
RWStructuredBuffer<uint2> pj_targets;
RWStructuredBuffer<uint4> pj_readiness;
RWStructuredBuffer<uint4> dg_root_routes;
RWStructuredBuffer<uint4> dg_root_readiness;
uint4 route_of(uint4 route,bool root)
{
    if(route.x==1u) return uint4(0xfffffffeu,0xffff0002u,dg_rank[dg_slots[route.y].y],dg_config[15]);
    if(route.x==2u) return dg_native(route.y);
    return root ? uint4(0u,0u,0u,0u) : uint4(RT_INVALID,0u,0u,dg_config[15]);
}

public void publish_discovered_instances(uint lane, uint mode)
{
    if (dg_proof_identity[0] != 0u && !dg_proofs_current()) { if (lane == 0u) dg_status[10] = 8u; return; }
    if(dg_status[3]!=0u || dg_status[6]!=RT_INVALID || dg_status[10]!=0u) return;
    if (mode == 1u)
    {
        if (lane < dg_status[0u] && dg_instances[2u * lane].x != 0u)
        {
            uint rank = dg_rank[lane];
            pj_instances[2u * rank] = dg_instances[2u * lane];
            pj_instances[2u * rank + 1u] = uint4(dg_instances[2u * lane + 1u].xy, 0u, 0u);
        }
        if(lane<dg_status[2]) { pj_routes[lane]=route_of(dg_edges[lane],false); pj_targets[lane]=dg_targets[lane]; }
        if(lane<rt_counts[RT_A_USES]) dg_root_routes[lane]=route_of(dg_roots[lane],true);
    }
    else if(lane==0u)
    {
        // Projection checks every instance call's ABI before lowering.
        // Original callers require a separate GPU ABI certification.
        pj_readiness[0]=uint4(dg_config[15],1u | (dg_proof_identity[0] != 0u ? 4u : 0u),dg_status[1],dg_status[2]);
        dg_root_readiness[0]=uint4(dg_config[15],1u,dg_status[1],rt_counts[RT_A_USES]);
    }
}
