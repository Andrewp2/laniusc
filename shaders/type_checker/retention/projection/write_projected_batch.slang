import shared.collectives.step_program;
__exported import type_checker.retention.projection.retained_lowering_columns;
import type_checker.retention.projection_rows.project_retained_body_rows_step;
import type_checker.retention.projection_rows.project_retained_body_side_tables_step;
import type_checker.retention.projection_rows.project_retained_string_bytes_step;
import type_checker.retention.projection.publish_retained_lowering_batch_step;

public void write_projected_batch(inout StepProgram program, Batch batch)
{
    uint capacity; uint stride;
    ob_core.GetDimensions(capacity, stride);
    for (uint row = program.lane; row < min(batch.rows, capacity); row += program.lanes)
        project_retained_body_rows(batch, row);

    uint first = pj_base_at(batch.lo, PJ_C_ROWS);
    uint last = pj_base_at(batch.hi, PJ_C_ROWS);
    uint words = pj_string_offsets[last] - pj_string_offsets[first];
    ob_string_data.GetDimensions(capacity, stride);
    for (uint row = program.lane; row < min(words, capacity); row += program.lanes)
        project_retained_string_bytes(batch, row);

    uint side_rows = 0u;
    for (uint table = 0u; table < PJ_SIDE_TABLES; ++table)
        side_rows = max(side_rows, pj_batch_side(batch, table));
    for (uint row = program.lane; row < side_rows; row += program.lanes)
        project_retained_body_side_tables(batch, row);
    if (program.lane == 0u) publish_retained_lowering_batch(batch);
}
