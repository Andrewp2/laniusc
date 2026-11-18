import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_types.export_row_scan;

groupshared uint4 g_values[256];
groupshared uint4 g_carry;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_GroupThreadID)
{
    uint n = rt_x_counts[RT_X_SCAN_N];
    uint blocks = (n + 255u) / 256u;
    if (tid.x == 0u) g_carry = uint4(0u, 0u, 0u, 0u);
    GroupMemoryBarrierWithGroupSync();
    for (uint chunk = 0u; chunk < blocks; chunk += 256u)
    {
        uint index = chunk + tid.x;
        uint4 value = index < blocks ? rt_x_blocks[index] : uint4(0u, 0u, 0u, 0u);
        g_values[tid.x] = value;
        GroupMemoryBarrierWithGroupSync();
        for (uint offset = 1u; offset < 256u; offset <<= 1u)
        {
            uint4 add = tid.x >= offset ? g_values[tid.x - offset] : uint4(0u, 0u, 0u, 0u);
            GroupMemoryBarrierWithGroupSync();
            g_values[tid.x] += add;
            GroupMemoryBarrierWithGroupSync();
        }
        uint4 carry = g_carry;
        if (index < blocks) rt_x_blocks[index] = carry + g_values[tid.x] - value;
        GroupMemoryBarrierWithGroupSync();
        if (tid.x == 255u) g_carry = carry + g_values[255u];
        GroupMemoryBarrierWithGroupSync();
    }
    if (tid.x == 0u)
    {
        uint4 total = g_carry;
        rt_x_counts[RT_X_SCAN_TOTAL] = total.x;
        rt_x_counts[RT_X_SCAN_TOTAL + 1u] = total.y;
        rt_x_counts[RT_X_SCAN_TOTAL + 2u] = total.z;
        rt_x_counts[RT_X_SCAN_TOTAL + 3u] = total.w;
    }
}
