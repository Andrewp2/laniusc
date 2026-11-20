import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.projection_schema.advance_retained_schema_round_step;
import shared.collectives.program_prefix_scan;
import type_checker.retention.projection_schema.count_retained_schema_requests_step;
import type_checker.retention.projection_schema.reserve_retained_schema_requests_step;
import type_checker.retention.projection_schema.emit_retained_schema_requests_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (ps_status[PS_PREPARE_FAILED] != 0u || ps_status[PS_PUBLISH_FAILED] != 0u)
    {
        if (program.leader)
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u);
        return;
    }

    bool resume = program_launch.options != 0u;
    if (!resume)
    {
        if (program.lane == 0u) advance_retained_schema_round(0u);
        if (!step_barrier(program)) return;
        if (ps_round[4] != 0u)
        {
            uint rows = ps_round_terms() + 1u;
            for (uint row = program.lane; row < rows; row += program.lanes)
                count_retained_schema_requests(row);
            if (!step_barrier(program)) return;
            if (!step_program_prefix_scan(
                    program, rows, ps_scan_a, ps_scan_b, ps_scan_total, ps_blocks)) return;
            if (!step_barrier(program)) return;
            for (uint row = program.lane; row < rows; row += program.lanes)
            {
                uint prior = ps_scan_b[row];
                uint count = ps_scan_a[row];
                if (count > 0xffffffffu - prior) InterlockedOr(ps_status[PS_ERROR], 2u);
                ps_scan_a[row] = prior + count;
            }
            if (!step_barrier(program)) return;
        }
    }
    if (program.lane == 0u) reserve_retained_schema_requests(resume);
    if (!step_barrier(program)) return;
    uint requests = sb_request_count[0u];
    for (uint row = program.lane; row < requests; row += program.lanes)
        emit_retained_schema_requests(row);

    step_program_end(program);
}
