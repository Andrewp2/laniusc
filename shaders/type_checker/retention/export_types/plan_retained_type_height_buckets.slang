// Export step 4 (one lane): exclusive bases of the height buckets, and the
// indirect arguments of the first translation round (height 1).
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.export.export_dispatch_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint base = 0u;
    for (uint height = 0u; height < RT_X_HEIGHTS; height++)
    {
        rt_x_counts[RT_X_BUCKET_BASE + height] = base;
        base += rt_x_counts[RT_X_BUCKET + height];
    }
    rt_x_counts[RT_X_ROUND] = 1u;
    set_dispatch(RT_D_ROUND, rt_x_counts[RT_X_BUCKET + 1u]);
}
