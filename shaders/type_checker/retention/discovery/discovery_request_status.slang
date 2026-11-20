import type_checker.retention.discovery.discovery_workspace;

public void finish_discovery_requests()
{
    if(dg_status[6]!=RT_INVALID) dg_status[16]=dg_errors[dg_status[6]].x;
    if(dg_status[6]!=RT_INVALID)
    {
        uint4 e=dg_errors[dg_status[6]];
        dg_status[17]=e.y; dg_status[18]=e.z; dg_status[19]=e.w;
    }
    if(rt_counts[RT_C_READY]==0u || rt_counts[RT_C_GENERATION]!=dg_config[15]) dg_status[10]=1u;
    // Resolution follows requests without a host check; it does
    // nothing after a failure or overflow, which the host reports.
    dg_status[12]=dg_status[3]!=0u || dg_status[6]!=RT_INVALID || dg_status[10]!=0u ? 1u : 0u;
}
