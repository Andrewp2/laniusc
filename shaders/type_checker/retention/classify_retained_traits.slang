import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retention_launch;
import type_checker.retention.export_types.scan_export_rows;
import type_checker.retention.export_traits.retained_trait_fact_export;
import type_checker.retention.export_traits.classify_retained_trait_facts_step;
import type_checker.retention.export_traits.reserve_retained_trait_facts_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    for (uint slot = 0u; slot < program_launch.slot; ++slot)
        if (rt_x_counts[RT_X_PROGRAM_FAILURE + slot] != 0u) return;
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = rt_x_counts[RT_X_SCAN_N];

    for (uint row = program.lane; row < rows; row += program.lanes)
        classify_retained_trait_facts(row);
    if (!step_barrier(program)) return;
    if (!scan_export_rows(program, rows, rt_x_tflags, rt_x_tscan, rt_x_counts, RT_X_TRAIT_TOTAL)) return;
    if (!step_barrier(program)) return;
    if (program.lane == 0u)
        reserve_retained_trait_facts(uint4(rt_x_counts[RT_X_TRAIT_TOTAL], rt_x_counts[RT_X_TRAIT_TOTAL + 1u],
            rt_x_counts[RT_X_TRAIT_TOTAL + 2u], rt_x_counts[RT_X_TRAIT_TOTAL + 3u]));
    step_program_end(program);
}
