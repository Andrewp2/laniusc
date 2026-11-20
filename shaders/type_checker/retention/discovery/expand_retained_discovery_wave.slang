import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.expand_discovery_wave;
import type_checker.retention.discovery.collect_discovery_requests_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (!expand_discovery_wave(program, configured_frontier(), dg_config[5], dg_config[6], program_launch.options)) return;
    step_program_end(program);
}
