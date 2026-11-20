import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retention_launch;
import type_checker.retention.export_rows.retained_body_side_tables;
import type_checker.retention.export_rows.retained_body_source_tables;
import type_checker.retention.export_rows.retained_body_side_tables_step;
import type_checker.retention.export_rows.clear_retained_body_text_step;
import type_checker.retention.export_rows.copy_retained_body_text_step;
import type_checker.retention.export_rows.retained_schema_rows_step;
import type_checker.retention.export_rows.retained_use_rows_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    for (uint slot = 0u; slot < program_launch.slot; ++slot)
        if (rt_x_counts[RT_X_PROGRAM_FAILURE + slot] != 0u) return;
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = rt_x_counts[RT_X_SCAN_N];

    uint side = 0u;
    for (uint table = 0u; table < RT_SIDE_TABLES; ++table) side = max(side, side_rows(table));
    uint tokens = job_token_rows();
    uint schema = max(max(side_rows(RT_SIDE_PARAMS), side_rows(RT_SIDE_FIELDS)),
                      max(variant_payload_rows(), variant_rows()));
    for (uint row = program.lane; row < side; row += program.lanes)
        write_retained_body_side_tables(row);
    for (uint row = program.lane; row < tokens; row += program.lanes)
        clear_retained_body_text(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < tokens; row += program.lanes)
        copy_retained_body_text(row);
    for (uint row = program.lane; row < schema; row += program.lanes)
        write_retained_schema_rows(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < rows; row += program.lanes)
        write_retained_use_rows(row);
    step_program_end(program);
}
