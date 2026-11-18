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
import type_checker.retention.export.source_tables;
import shared.syntax.hir_records;

// Publishes the job's first fault as the build's, located at the first
// token of its row when the fault names one.
void record_fault()
{
    if (rt_counts[RT_C_FAULT] != 0u) return;
    uint key = rt_counts[RT_C_FAULT_KEY];
    uint reason = key == 0xffffffffu ? RT_FAULT_UNKNOWN : key & 0xffu;
    uint row = key >> 8u;
    rt_counts[RT_C_FAULT_JOB] = rt_counts[RT_C_JOBS] - 1u;
    if (key != 0xffffffffu && row != RT_FAULT_NO_ROW && valid_row(row))
    {
        uint file = compact_hir_links[row].file_id;
        RtJobToken token = job_token(compact_hir_core[row].token_start);
        rt_counts[RT_C_FAULT_FILE] = file;
        rt_counts[RT_C_FAULT_BYTE] = token.start - job_file_start(file);
        rt_counts[RT_C_FAULT_LEN] = max(token.len, 1u);
        reason |= RT_FAULT_LOCATED;
    }
    rt_counts[RT_C_FAULT] = reason;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint staged = rt_counts[RT_C_STAGED_DIR];
    // The job identity is retained even when no declaration was staged.
    // Reserve before deciding the transaction so lack of job space rolls
    // back all the job's other arenas and requests growth in the same way.
    uint job = rt_alloc(RT_A_JOBS, 1u);
    if (rt_counts[RT_C_OVERFLOW] == 0u)
    {
        rt_jobs[job] = uint4(rt_counts[RT_C_LIBRARY], rt_counts[RT_C_UNIT], rt_counts[RT_C_GENERATION], 0u);
        rt_counts[RT_C_JOB_STATE] = RT_JOB_COMMITTED;
        rt_counts[RT_C_JOBS] += 1u;
        rt_counts[RT_C_INVARIANT_TOTAL] += rt_counts[RT_C_INVARIANTS];
        rt_counts[RT_C_INCOMPLETE_TOTAL] += rt_counts[RT_C_INCOMPLETE];
        if (rt_counts[RT_C_INVARIANTS] != 0u || rt_counts[RT_C_INCOMPLETE] != 0u)
        {
            rt_counts[RT_C_READY] = 0u;
            record_fault();
        }
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
