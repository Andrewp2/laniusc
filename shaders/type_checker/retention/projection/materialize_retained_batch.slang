import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.retained_lowering_columns;
import type_checker.retention.projection_rows.project_retained_body_rows_step;
import type_checker.retention.projection_rows.project_retained_body_side_tables_step;
import type_checker.retention.projection_rows.project_retained_string_bytes_step;
import type_checker.retention.projection.publish_retained_lowering_batch_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    Batch batch = pj_batch();
    uint capacity; uint stride;
    ob_core.GetDimensions(capacity, stride);
    for (uint row = program.lane; row < min(batch.rows, capacity); row += program.lanes)
        project_retained_body_rows(row);

    uint first = pj_base_at(batch.lo, PJ_C_ROWS);
    uint last = pj_base_at(batch.hi, PJ_C_ROWS);
    uint words = pj_string_offsets[last] - pj_string_offsets[first];
    ob_string_data.GetDimensions(capacity, stride);
    for (uint row = program.lane; row < min(words, capacity); row += program.lanes)
        project_retained_string_bytes(row);

    uint side_rows = 0u;
    for (uint table = 0u; table < PJ_SIDE_TABLES; ++table)
        side_rows = max(side_rows, pj_batch_side(table));
    for (uint row = program.lane; row < side_rows; row += program.lanes)
        project_retained_body_side_tables(row);
    if (program.lane == 0u) publish_retained_lowering_batch();
    step_program_end(program);
}
