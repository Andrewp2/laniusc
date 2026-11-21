import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retention_launch;
import type_checker.retention.export_rows.retained_body_side_tables;
import type_checker.retention.export_rows.retained_body_side_tables_step;
import type_checker.retention.export_rows.write_retained_body_text;
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
    uint schema = max(max(side_rows(RT_SIDE_PARAMS), side_rows(RT_SIDE_FIELDS)),
                      max(variant_payload_rows(), variant_rows()));
    uint segments = rt_x_counts[RT_X_SCAN_TOTAL + 3u];
    uint seg_base = rt_x_counts[RT_X_BASE + RT_A_SEGMENTS];
    if (seg_base != RT_INVALID && rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] != RT_INVALID)
        for (uint ordinal = group.x; ordinal < segments; ordinal += program.groups)
            write_retained_body_text(ordinal, seg_base + ordinal, local.x, STEP_PROGRAM_GROUP_LANES);
    for (uint row = program.lane; row < side; row += program.lanes)
        write_retained_body_side_tables(row);
    for (uint row = program.lane; row < rows; row += program.lanes)
        write_retained_use_rows(row);
    // Required trait receiver terms are interned by the parameter side lane.
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < schema; row += program.lanes)
        write_retained_schema_rows(row);
    step_program_end(program);
}
