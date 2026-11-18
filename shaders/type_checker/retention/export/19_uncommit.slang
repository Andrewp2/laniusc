// Export step 19, recorded only when the host does not accept a job whose
// export it submitted before the job's statuses were read (the frontend or
// the lowering asks for a retry, or the build fails). One lane per hash
// slot and per declaration. Restores the store to the job's watermark
// whether steps 16 and 17 committed the job or rolled it back: a cleared
// slot or definition points at a record at or past the watermark, and lane
// 0 restores every counter the job changed from the words step 0 saved.
import type_checker.retention.retention_store;
import type_checker.retention.export.common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    uint slots; uint stride;
    rt_decl_slot.GetDimensions(slots, stride);
    if (lane < slots && rt_decl_slot[lane] >= rt_counts[RT_C_JOB_BASE + RT_A_DECLS]) rt_decl_slot[lane] = 0u;
    rt_param_slot.GetDimensions(slots, stride);
    if (lane < slots && rt_param_slot[lane] >= rt_counts[RT_C_JOB_BASE + RT_A_PARAMS]) rt_param_slot[lane] = 0u;
    rt_term_slot.GetDimensions(slots, stride);
    if (lane < slots && rt_term_slot[lane] >= rt_counts[RT_C_JOB_BASE + RT_A_TERMS]) rt_term_slot[lane] = 0u;
    // A definition step 17 published points at a staged entry of the job.
    rt_decl_def.GetDimensions(slots, stride);
    if (lane < slots && rt_decl_def[lane] > rt_counts[RT_C_STAGED_DIR]) rt_decl_def[lane] = 0u;
    if (lane != 0u) return;
    for (uint arena = 0u; arena < RT_ARENAS; arena++) rt_counts[arena] = rt_counts[RT_C_JOB_BASE + arena];
    for (uint spare = 0u; spare < 4u; spare++) rt_counts[RT_C_SPARE + spare] = rt_counts[RT_C_JOB_SPARE + spare];
    rt_counts[RT_C_JOBS] = rt_counts[RT_C_SAVED_JOBS];
    rt_counts[RT_C_INVARIANT_TOTAL] = rt_counts[RT_C_SAVED_INVARIANT_TOTAL];
    rt_counts[RT_C_INCOMPLETE_TOTAL] = rt_counts[RT_C_SAVED_INCOMPLETE_TOTAL];
    rt_counts[RT_C_READY] = rt_counts[RT_C_SAVED_READY];
    // A store that was ready before the job had no fault; the job's fault goes with it.
    if (rt_counts[RT_C_SAVED_READY] != 0u) rt_counts[RT_C_FAULT] = 0u;
    rt_counts[RT_C_CONFLICTS] = rt_counts[RT_C_SAVED_CONFLICTS];
    rt_counts[RT_C_JOB_STATE] = RT_JOB_ROLLED_BACK;
}
