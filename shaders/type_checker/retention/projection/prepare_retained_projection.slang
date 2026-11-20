import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.plan_retained_instance_projection_step;

RWStructuredBuffer<uint> pj_scan_sums;
RWStructuredBuffer<uint> pj_scan_total;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint ranks = pj_instance_count();
    for (uint row = program.lane; row < max(1u, ranks); row += program.lanes)
        plan_retained_instance_projection(row);
    if (!step_barrier(program)) return;
    if (pj_status[PJ_S_INPUT_ERROR] == 0u)
    {
        for (uint column = 0u; column < PJ_COLUMNS; ++column)
        {
            if (!step_program_prefix_scan_strided(program, ranks, pj_base, pj_base, pj_scan_total,
                    pj_scan_sums, column, PJ_COLUMNS, column)) return;
            if (!step_barrier(program)) return;
        }
        if (program.lane < PJ_COLUMNS)
        {
            uint column = program.lane;
            uint total = pj_scan_total[column];
            pj_base[ranks * PJ_COLUMNS + column] = total;
            pj_status[PJ_S_TOTALS + column] = total;
        }
    }
    step_program_end(program);
}
