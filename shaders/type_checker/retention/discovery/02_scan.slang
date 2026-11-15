import type_checker.retention.discovery.dg_common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lane = dg_lane(id); uint count = dg_config[2] - dg_config[1];
    if (lane >= count) return;
    uint instance = dg_config[1] + lane;
    if (dg_config[0] == 0u)
    {
        uint decl = dg_instances[2u * instance].x;
        uint entry = dg_entry(decl);
        dg_scan_a[lane] = entry == RT_INVALID ? 0u : rt_dir[entry * RT_DIR_WORDS + 3u].x;
    }
    else if (dg_config[0] == 1u)
    {
        uint value = dg_scan(lane);
        if (lane >= dg_config[8]) value += dg_scan(lane - dg_config[8]);
        if (dg_config[9] == 0u) dg_scan_b[lane] = value; else dg_scan_a[lane] = value;
    }
    else
    {
        uint start = lane == 0u ? 0u : dg_scan(lane-1u);
        uint end = dg_scan(lane);
        uint4 old = dg_instances[2u * instance + 1u];
        dg_instances[2u * instance + 1u] = uint4(dg_config[3] + start,end-start,old.z,0u);
        if (lane + 1u == count)
        {
            uint demand = dg_config[3] + end;
            dg_status[2] = demand; dg_status[5] = demand;
            uint capacity; uint stride; dg_edges.GetDimensions(capacity,stride);
            if (demand > capacity) InterlockedOr(dg_status[3],2u);
        }
    }
}
