import shared.collectives.step_program;
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import shared.collectives.program_prefix_scan;
import type_checker.retention.projection_schema.count_retained_schema_requests_step;
import type_checker.retention.projection_schema.reserve_retained_schema_requests_step;
import type_checker.retention.projection_schema.emit_retained_schema_requests_step;

public bool prepare_schema_round_requests(inout StepProgram program, bool resume)
{
    if (!resume && ps_round[4] != 0u)
    {
        uint rows = ps_round_terms() + 1u;
        for (uint row = program.lane; row < rows; row += program.lanes)
            count_retained_schema_requests(row);
        if (!step_barrier(program)) return false;
        if (!step_program_prefix_scan(
                program, rows, ps_scan_a, ps_scan_b, ps_scan_total, ps_blocks)) return false;
        if (!step_barrier(program)) return false;
        for (uint row = program.lane; row < rows; row += program.lanes)
        {
            uint prior = ps_scan_b[row];
            uint count = ps_scan_a[row];
            if (count > 0xffffffffu - prior) InterlockedOr(ps_status[PS_ERROR], 2u);
            ps_scan_a[row] = prior + count;
        }
        if (!step_barrier(program)) return false;
    }
    if (program.lane == 0u) reserve_retained_schema_requests(resume);
    if (!step_barrier(program)) return false;
    uint requests = sb_request_count[0u];
    for (uint row = program.lane; row < requests; row += program.lanes)
        emit_retained_schema_requests(row);
    return true;
}
