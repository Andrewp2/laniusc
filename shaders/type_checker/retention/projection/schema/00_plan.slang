import type_checker.retention.projection.schema.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lane = ps_lane(id);
    uint n = ps_config[1]-ps_config[0];
    if (lane > n) return;
    uint entry = lane == 0u ? RT_INVALID : ps_entry(ps_config[0]+lane-1u);
    ps_scan_a[lane] = entry == RT_INVALID ? 0u : rt_dir[entry*RT_DIR_WORDS+2u].z;
    if (lane == 0u)
    {
        ps_status[0] = 0u;
        ps_status[1] = rt_counts[RT_A_TERMS];
        ps_status[2] = rt_counts[RT_C_READY] == 0u || rt_counts[RT_C_GENERATION] != ps_config[6] ? 1u : 0u;
    }
}
