// Export step 4 (one lane): exclusive bases of the height buckets, and the
// indirect arguments of the first translation round (height 1).
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public void plan_retained_type_height_buckets()
{
    uint base = 0u;
    for (uint height = 0u; height < RT_X_HEIGHTS; height++)
    {
        rt_x_counts[RT_X_BUCKET_BASE + height] = base;
        base += rt_x_counts[RT_X_BUCKET + height];
    }
}
