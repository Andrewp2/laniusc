import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retention_launch;
import type_checker.retention.export_rows.stage_retained_declarations_step;
import type_checker.retention.export_rows.retained_body_rows_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    for (uint slot = 0u; slot < program_launch.slot; ++slot)
        if (rt_x_counts[RT_X_PROGRAM_FAILURE + slot] != 0u) return;
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = rt_x_counts[RT_X_SCAN_N];

    for (uint row = program.lane; row < rows; row += program.lanes)
        stage_retained_declarations(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < rows; row += program.lanes)
        write_retained_body_rows(row);
    step_program_end(program);
}
