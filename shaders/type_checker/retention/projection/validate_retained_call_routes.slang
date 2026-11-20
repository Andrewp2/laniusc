import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.validate_projection_call_routes;
import type_checker.retention.projection.certify_projection_root_calls;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (!validate_projection_call_routes(program)) return;
    if ((program_launch.options & 1u) != 0u)
    {
        if (!certify_projection_root_calls(program)) return;
    }
    step_program_end(program);
}
