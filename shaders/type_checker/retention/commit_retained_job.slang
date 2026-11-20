import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retention_launch;
import type_checker.retention.export_traits.retained_trait_facts_step;
import type_checker.retention.export_traits.link_retained_bound_calls_step;
import type_checker.retention.export.finalize_retained_export_rows_step;
import type_checker.retention.export.commit_retained_export_step;
import type_checker.retention.export.publish_retained_directory_entries_step;
import type_checker.retention.export.roll_back_retained_export_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    for (uint slot = 0u; slot < program_launch.slot; ++slot)
        if (rt_x_counts[RT_X_PROGRAM_FAILURE + slot] != 0u) return;
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = rt_x_counts[RT_X_SCAN_N];

    for (uint row = program.lane; row < rows; row += program.lanes)
        write_retained_trait_facts(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < rows; row += program.lanes)
        link_retained_bound_calls(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < rows; row += program.lanes)
        finalize_retained_export_rows(row);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) commit_retained_export();
    if (!step_barrier(program)) return;

    if (rt_counts[RT_C_JOB_STATE] == RT_JOB_COMMITTED)
    {
        uint entries = rt_counts[RT_A_DIR] - rt_counts[RT_C_STAGED_DIR];
        for (uint row = program.lane; row < entries; row += program.lanes)
            publish_retained_directory_entries(row);
    }
    else
    {
        uint declarations; uint parameters; uint terms; uint stride;
        rt_decl_slot.GetDimensions(declarations, stride);
        rt_param_slot.GetDimensions(parameters, stride);
        rt_term_slot.GetDimensions(terms, stride);
        for (uint row = program.lane; row < max(declarations, max(parameters, terms)); row += program.lanes)
            roll_back_retained_export(row);
    }
    step_program_end(program);
}
