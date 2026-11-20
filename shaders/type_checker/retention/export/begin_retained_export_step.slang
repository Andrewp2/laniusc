// Export step 0 (one lane): open the job's transaction. Every arena keeps
// its counter as the job's watermark; a failed job restores them, so
// nothing it allocated becomes visible. Clears the job's status words and
// publishes the job's live HIR count.
import shared.syntax.hir_records;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public void begin_retained_export()
{
    for (uint arena = 0u; arena < RT_ARENAS; arena++)
    {
        rt_counts[RT_C_JOB_BASE + arena] = rt_counts[arena];
        rt_counts[RT_C_DEMAND + arena] = 0u;
    }
    for (uint spare = 0u; spare < 4u; spare++) rt_counts[RT_C_JOB_SPARE + spare] = rt_counts[RT_C_SPARE + spare];
    rt_counts[RT_C_SAVED_JOBS] = rt_counts[RT_C_JOBS];
    rt_counts[RT_C_SAVED_INVARIANT_TOTAL] = rt_counts[RT_C_INVARIANT_TOTAL];
    rt_counts[RT_C_SAVED_INCOMPLETE_TOTAL] = rt_counts[RT_C_INCOMPLETE_TOTAL];
    rt_counts[RT_C_SAVED_READY] = rt_counts[RT_C_READY];
    rt_counts[RT_C_SAVED_CONFLICTS] = rt_counts[RT_C_CONFLICTS];
    rt_counts[RT_C_OVERFLOW] = 0u;
    rt_counts[RT_C_INVARIANTS] = 0u;
    rt_counts[RT_C_INCOMPLETE] = 0u;
    rt_counts[RT_C_FIRST_INVARIANT] = 0xffffffffu;
    rt_counts[RT_C_FAULT_KEY] = 0xffffffffu;
    rt_counts[RT_C_JOB_STATE] = RT_JOB_OPEN;
    rt_counts[RT_C_LIBRARY] = job_library();
    rt_counts[RT_C_UNIT] = job_unit();
    rt_counts[RT_C_STAGED_DIR] = rt_counts[RT_A_DIR];

    rt_x_counts[RT_X_SCAN_N] = hir_count();
}
