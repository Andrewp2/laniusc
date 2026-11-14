// Export step 16 (one lane): decide the job's transaction. A job commits
// when no arena or table overflowed; its staged directory entries are then
// published by step 17. Otherwise every arena counter and spare counter is
// restored to the job's watermark and step 18 clears the hash slots that
// point at records the job allocated, so no partial or duplicated record of
// the job stays reachable. Invariant failures do not roll a job back: they
// are reported in the status words and mark the affected entries incomplete.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.dispatch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint staged = rt_counts[RT_C_STAGED_DIR];
    if (rt_counts[RT_C_OVERFLOW] == 0u)
    {
        rt_counts[RT_C_JOB_STATE] = RT_JOB_COMMITTED;
        rt_counts[RT_C_JOBS] += 1u;
        set_dispatch(RT_D_COMMIT_DIR, rt_counts[RT_A_DIR] - staged);
        set_dispatch(RT_D_ROLLBACK, 0u);
        return;
    }
    for (uint arena = 0u; arena < RT_ARENAS; arena++) rt_counts[arena] = rt_counts[RT_C_JOB_BASE + arena];
    for (uint spare = 0u; spare < 4u; spare++) rt_counts[RT_C_SPARE + spare] = rt_counts[RT_C_JOB_SPARE + spare];
    rt_counts[RT_C_JOB_STATE] = RT_JOB_ROLLED_BACK;
    rt_counts[RT_C_ROLLBACKS] += 1u;
    uint slots; uint stride;
    uint most = 0u;
    rt_decl_slot.GetDimensions(slots, stride); most = max(most, slots);
    rt_param_slot.GetDimensions(slots, stride); most = max(most, slots);
    rt_term_slot.GetDimensions(slots, stride); most = max(most, slots);
    set_dispatch(RT_D_COMMIT_DIR, 0u);
    set_dispatch(RT_D_ROLLBACK, most);
}
