import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.substitution.run_retained_substitution;
import type_checker.retention.substitution.retained_substitution_workspace;

StructuredBuffer<uint4> sb_requests;
StructuredBuffer<uint> sb_request_count;

struct BufferRequests : ISubstitutionRequests
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
    if (!run_retained_substitution(program, program_launch.options, sb_config[SB_CFG_RUN], BufferRequests())) return;
    step_program_end(program);
}
