import shared.collectives.step_program;
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.projection_schema.reserve_retained_schema_requests_step;
import type_checker.retention.projection_schema.emit_retained_schema_requests_step;

public bool prepare_schema_round_requests(inout StepProgram program, bool resume)
{
    if (resume)
    {
        if (program.lane == 0u) ps_round[3u] = 0u;
        if (!step_barrier(program)) return false;
    }
    uint end = ps_round[1u];
    for (uint term = ps_round_lo() + program.lane; term < end; term += program.lanes)
        emit_retained_schema_requests(term);
    if (!step_barrier(program)) return false;
    if (program.lane == 0u) reserve_retained_schema_requests(resume);
    return true;
}
