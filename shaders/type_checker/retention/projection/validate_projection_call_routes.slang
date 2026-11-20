import shared.collectives.step_program;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.validate_projected_call_routes_step;
import type_checker.retention.projection.report_retained_projection_errors_step;
import type_checker.retention.projection.plan_retained_lowering_batches_step;

public bool validate_projection_call_routes(inout StepProgram program)
{
    uint rows = pj_total(PJ_C_ROWS);
    for (uint row = program.lane; row < rows; row += program.lanes)
        validate_projected_call_routes(row);
    if (!step_barrier(program)) return false;
    if (program.lane == 0u) report_retained_projection_errors();
    if (!step_barrier(program)) return false;
    uint width = max(1u, pj_config[PJ_CFG_BATCH_ROWS]);
    uint batches = rows == 0u ? 1u : 1u + (rows - 1u) / width;
    for (uint row = program.lane; row < batches; row += program.lanes)
        plan_retained_lowering_batches(row);
    return true;
}
