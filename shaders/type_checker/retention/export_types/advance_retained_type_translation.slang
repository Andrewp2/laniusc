// Export step 7 (one lane): the next translation height and its indirect
// arguments. The host records steps 6 and 7 once per height below
// RT_X_HEIGHTS; rounds past the job's largest height dispatch nothing.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.export.export_dispatch_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint height = rt_x_counts[RT_X_ROUND] + 1u;
    rt_x_counts[RT_X_ROUND] = height;
    set_dispatch(RT_D_ROUND, height < RT_X_HEIGHTS ? rt_x_counts[RT_X_BUCKET + height] : 0u);
}
