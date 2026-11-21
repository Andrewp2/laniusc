import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retention_launch;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.export_rows.retained_body_side_tables;
import type_checker.retention.export_types.scan_export_rows;
import type_checker.retention.export.begin_retained_export_step;
import type_checker.retention.export_types.intern_retained_generic_parameters_step;
import type_checker.retention.export_types.index_retained_declaration_tokens_step;
import type_checker.retention.export_types.collect_retained_body_metadata_step;
import type_checker.retention.export_types.count_retained_type_heights_step;
import type_checker.retention.export_types.translate_retained_canonical_types_step;
import type_checker.retention.export_types.reserve_retained_export_rows_step;

import type_checker.retention.export_rows.stage_retained_declarations_step;
import type_checker.retention.export_rows.retained_body_rows_step;
[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (program.lane == 0u) begin_retained_export();
    if (!step_barrier(program)) return;

    uint params; uint stride;
    compact_generic_params.GetDimensions(params, stride);
    params = min(params, compact_generic_param_count[0u]);
    uint rows = rt_x_counts[RT_X_SCAN_N];
    uint variants = variant_rows();
    uint records = min(rt_input_ct_counts[CT_COUNT_NEXT_RECORD], export_record_capacity());
    for (uint row = program.lane; row < params; row += program.lanes)
        intern_retained_generic_parameters(row);
    for (uint row = program.lane; row < max(rows, variants); row += program.lanes)
        index_retained_declaration_tokens(row);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < rows; row += program.lanes)
        collect_retained_body_metadata(row);
    for (uint row = program.lane; row < records; row += program.lanes)
        count_retained_type_heights(row);
    if (!step_barrier(program)) return;

    for (uint block = 0u; block < (RT_X_HEIGHTS + 31u) / 32u; ++block)
    {
        uint occupied = rt_x_counts[RT_X_HEIGHT_MASK + block];
        while (occupied != 0u)
        {
            uint height = block * 32u + uint(firstbitlow(occupied));
            for (uint record = CT_FIRST_RECORD + program.lane; record < records; record += program.lanes)
                translate_retained_canonical_types(record, height);
            if (!step_barrier(program)) return;
            occupied &= occupied - 1u;
        }
    }

    if (!scan_export_rows(program, rows, rt_x_flags, rt_x_scan, rt_x_counts, RT_X_SCAN_TOTAL)) return;
    if (!step_barrier(program)) return;
    if (program.lane == 0u) reserve_retained_export_rows();
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < rows; row += program.lanes)
        stage_retained_declarations(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < rows; row += program.lanes)
        write_retained_body_rows(row);
    step_program_end(program);
}
