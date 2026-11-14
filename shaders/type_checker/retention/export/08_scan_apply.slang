import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.scan_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint group = scan_group(gid);
    uint index = group * 256u + tid.x;
    if (index < rt_x_counts[RT_X_SCAN_N]) rt_x_scan[index] += rt_x_blocks[group];
}
