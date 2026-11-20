// Export step 18: one lane per hash slot of a rolled-back job. Clears every
// slot that points at a record at or past the job's watermark. Linear
// probing stays sound: a key inserted before the job stopped at a slot that
// was occupied then, so no older probe chain crosses a slot the job filled.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public void roll_back_retained_export(uint slot)
{
    if (rt_counts[RT_C_JOB_STATE] != RT_JOB_ROLLED_BACK) return;
    uint slots; uint stride;
    rt_decl_slot.GetDimensions(slots, stride);
    if (slot < slots && rt_decl_slot[slot] >= rt_counts[RT_C_JOB_BASE + RT_A_DECLS]) rt_decl_slot[slot] = 0u;
    rt_param_slot.GetDimensions(slots, stride);
    if (slot < slots && rt_param_slot[slot] >= rt_counts[RT_C_JOB_BASE + RT_A_PARAMS]) rt_param_slot[slot] = 0u;
    rt_term_slot.GetDimensions(slots, stride);
    if (slot < slots && rt_term_slot[slot] >= rt_counts[RT_C_JOB_BASE + RT_A_TERMS]) rt_term_slot[slot] = 0u;
}
