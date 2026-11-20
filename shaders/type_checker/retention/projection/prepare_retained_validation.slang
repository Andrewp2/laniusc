import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection_rows.retained_projection_type_tables;
import type_checker.retention.projection_rows.clear_projected_type_tables_step;
import type_checker.retention.projection_rows.project_closed_type_arguments_step;
import type_checker.retention.projection_rows.compute_closed_type_layouts_step;
import type_checker.retention.projection_rows.clear_projected_row_errors_step;
import type_checker.retention.projection_rows.project_retained_expression_edges_step;
import type_checker.retention.projection_rows.project_retained_pattern_roots_step;
import type_checker.retention.projection_rows.project_retained_pattern_payloads_step;

import type_checker.retention.projection_rows.scan_projected_string_word_counts;
import type_checker.retention.projection.validate_projected_semantic_rows_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint type_rows = pj_type_rows();
    for (uint row = program.lane; row < type_rows; row += program.lanes)
    {
        clear_projected_type_tables(row);
        project_closed_type_arguments(row);
    }
    uint rows = pj_total(PJ_C_ROWS);
    for (uint row = program.lane; row < rows; row += program.lanes)
        clear_projected_row_errors(row);
    if (!step_barrier(program)) return;

    uint terms = min(min(rt_counts[RT_A_TERMS], rt_capacity(RT_A_TERMS)), type_rows);
    uint layout_rounds = pj_config[PJ_CFG_LAYOUT_ROUNDS];
    uint completed_layouts = 0u;
    for (uint round = 0u; round < layout_rounds; ++round)
    {
        // Clear the next word while other lanes may still read the previous one.
        uint changed = PJ_S_PROGRAM_CHANGED + (round & 1u);
        if (program.lane == 0u) pj_status[changed] = 0u;
        if (!step_barrier(program)) return;
        for (uint row = RT_FIRST_TERM + program.lane; row < terms; row += program.lanes)
            compute_closed_type_layouts(row, changed);
        if (!step_barrier(program)) return;
        completed_layouts = pj_status[changed];
        if (completed_layouts == 0u) break;
    }
    if (program.lane == 0u) pj_status[PJ_S_LAYOUT_CHANGED] = completed_layouts;

    for (uint row = program.lane; row < rows; row += program.lanes)
        project_retained_expression_edges(row);

    uint arms = pj_total(PJ_C_SIDE + PJ_SIDE_MATCH_ARMS);
    uint payloads = pj_total(PJ_C_SIDE + PJ_SIDE_MATCH_PAYLOADS);
    // Edges write the expression-parent column. Roots initialize the matched
    // type column and write the payload arity of parent rows.
    for (uint row = program.lane; row < max(arms, payloads); row += program.lanes)
        project_retained_pattern_roots(row);
    uint completed_payloads = 0u;
    if (payloads != 0u)
    {
        if (!step_barrier(program)) return;
        uint pattern_rounds = pj_config[PJ_CFG_PATTERN_ROUNDS];
        for (uint round = 0u; round < pattern_rounds; ++round)
        {
            uint changed = PJ_S_PROGRAM_CHANGED + (round & 1u);
            if (program.lane == 0u) pj_status[changed] = 0u;
            if (!step_barrier(program)) return;
            for (uint row = program.lane; row < payloads; row += program.lanes)
                project_retained_pattern_payloads(row, changed);
            if (!step_barrier(program)) return;
            completed_payloads = pj_status[changed];
            if (completed_payloads == 0u) break;
        }
    }
    if (program.lane == 0u) pj_status[PJ_S_PATTERN_CHANGED] = completed_payloads;
    if (!step_barrier(program)) return;
    if (!scan_projected_string_word_counts(program, rows)) return;

    for (uint row = program.lane; row < rows; row += program.lanes)
        validate_projected_semantic_row(row);
    step_program_end(program);
}
