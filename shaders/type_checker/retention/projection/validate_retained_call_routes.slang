import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.validate_projected_call_routes_step;
import type_checker.retention.projection.report_retained_projection_errors_step;
import type_checker.retention.projection.plan_retained_lowering_batches_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = pj_total(PJ_C_ROWS);
    for (uint row = program.lane; row < rows; row += program.lanes)
        validate_projected_call_routes(row);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) report_retained_projection_errors();
    if (!step_barrier(program)) return;
    uint width = max(1u, pj_config[PJ_CFG_BATCH_ROWS]);
    uint batches = rows == 0u ? 1u : 1u + (rows - 1u) / width;
    for (uint row = program.lane; row < batches; row += program.lanes)
        plan_retained_lowering_batches(row);
    step_program_end(program);
}
