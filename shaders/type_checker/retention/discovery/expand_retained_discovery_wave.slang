import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_frontier;
import type_checker.retention.discovery.expand_discovery_wave;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    uint groups = discovery_wave_groups(program_launch.groups, 0u);
    if (group.x >= groups) return;
    StepProgram program = step_program_begin(group, local, groups, program_launch.slot);
    if (!substitute_discovery_requests(program, dg_config[5u], dg_config[6u], program_launch.options)) return;
    if (dg_config[12u] != 0u)
    {
        if (!step_barrier(program)) return;
        if (program.lane == 0u) advance_discovery_frontier(dg_config[8u], false);
    }
    step_program_end(program);
}
