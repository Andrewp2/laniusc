// Export step 17: one lane per staged directory entry of a committed job.
// Publishes the entry as its declaration's definition. A declaration that a
// committed entry already defines is a conflict: the first definition stays
// and the conflict is counted.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    uint entry = rt_counts[RT_C_STAGED_DIR] + lane;
    if (rt_counts[RT_C_JOB_STATE] != RT_JOB_COMMITTED || entry >= rt_counts[RT_A_DIR]) return;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint prior;
    InterlockedCompareExchange(rt_decl_def[d0.x], 0u, entry + 1u, prior);
    if (prior != 0u)
    {
        InterlockedAdd(rt_counts[RT_C_CONFLICTS], 1u);
        rt_invariant(RT_INV_DUPLICATE_DECL);
        // The chosen pointer is never consumable from a conflicting build.
        // Publication conflicts happen after step 16's reduction.
        InterlockedAdd(rt_counts[RT_C_INVARIANT_TOTAL], 1u);
        InterlockedAnd(rt_counts[RT_C_READY], 0u);
        uint previous_flags;
        InterlockedOr(rt_dir[entry * RT_DIR_WORDS + 3u].w, RT_DIR_INCOMPLETE, previous_flags);
        if ((previous_flags & RT_DIR_INCOMPLETE) == 0u)
        {
            InterlockedAdd(rt_counts[RT_C_INCOMPLETE], 1u);
            InterlockedAdd(rt_counts[RT_C_INCOMPLETE_TOTAL], 1u);
        }
    }
    d0.w = RT_DIR_COMMITTED;
    rt_dir[entry * RT_DIR_WORDS] = d0;
}
