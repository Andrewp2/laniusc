// Export step 0 (one lane): open the job's transaction. Every arena keeps
// its counter as the job's watermark; a failed job restores them, so
// nothing it allocated becomes visible. Clears the job's status words and
// publishes the indirect arguments of the row-, parameter- and record-
// parallel steps from the job's live counts.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.dispatch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    for (uint arena = 0u; arena < RT_ARENAS; arena++)
    {
        rt_counts[RT_C_JOB_BASE + arena] = rt_counts[arena];
        rt_counts[RT_C_DEMAND + arena] = 0u;
    }
    for (uint spare = 0u; spare < 4u; spare++) rt_counts[RT_C_JOB_SPARE + spare] = rt_counts[RT_C_SPARE + spare];
    rt_counts[RT_C_OVERFLOW] = 0u;
    rt_counts[RT_C_INVARIANTS] = 0u;
    rt_counts[RT_C_FIRST_INVARIANT] = 0xffffffffu;
    rt_counts[RT_C_JOB_STATE] = RT_JOB_OPEN;
    rt_counts[RT_C_LIBRARY] = job_library();
    rt_counts[RT_C_UNIT] = job_unit();
    rt_counts[RT_C_STAGED_DIR] = rt_counts[RT_A_DIR];

    uint rows = hir_count();
    uint params; uint stride;
    compact_generic_params.GetDimensions(params, stride);
    params = min(compact_generic_param_count[0u], params);
    uint records = min(ct_counts[CT_COUNT_NEXT_RECORD], ct_record_capacity());
    rt_x_counts[RT_X_SCAN_N] = rows;
    set_dispatch(RT_D_HIR, rows);
    set_dispatch(RT_D_PARAMS, params);
    set_dispatch(RT_D_RECORDS, records);
    set_dispatch(RT_D_ROUND, 0u);
    set_dispatch(RT_D_SIDE, 0u);
    set_dispatch(RT_D_SCHEMA, 0u);
    set_dispatch(RT_D_COMMIT_DIR, 0u);
    set_dispatch(RT_D_ROLLBACK, 0u);
}
