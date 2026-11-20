import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.emit_retained_projection_substitution_requests_step;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.run_retained_substitution;

struct ProjectionRequests : ISubstitutionRequests
{
    uint count() { return sb_request_count[0u]; }
    uint capacity()
    {
        uint rows; uint stride;
        sb_requests.GetDimensions(rows, stride);
        return rows;
    }
    uint4 request(uint row) { return sb_requests[row]; }
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint requests = pj_total(PJ_C_REQUESTS);
    for (uint row = program.lane; row < max(1u, requests); row += program.lanes)
        emit_retained_projection_substitution_request(row);
    if (!step_barrier(program)) return;
    if (!run_retained_substitution(
            program, program_launch.options, sb_config[SB_CFG_RUN], ProjectionRequests())) return;
    step_program_end(program);
}
