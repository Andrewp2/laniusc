import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_types.export_row_scan;

groupshared uint4 g_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint group = scan_group(gid);
    uint index = group * 256u + tid.x;
    uint n = rt_x_counts[RT_X_SCAN_N];
    uint4 value = index < n ? rt_x_flags[index] : uint4(0u, 0u, 0u, 0u);
    g_values[tid.x] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint offset = 1u; offset < 256u; offset <<= 1u)
    {
        uint4 add = tid.x >= offset ? g_values[tid.x - offset] : uint4(0u, 0u, 0u, 0u);
        GroupMemoryBarrierWithGroupSync();
        g_values[tid.x] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    if (index < n) rt_x_scan[index] = g_values[tid.x] - value;
    if (tid.x == 255u && group * 256u < n) rt_x_blocks[group] = g_values[255u];
}
