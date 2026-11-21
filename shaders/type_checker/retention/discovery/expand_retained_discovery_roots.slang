import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.expand_discovery_wave;
import type_checker.retention.discovery.discovery_term_counts;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (!expand_discovery_wave(program, configured_frontier(), dg_config[5u], dg_config[6u], program_launch.options)) return;
    if (!step_barrier(program)) return;

    uint terms = rt_counts[RT_A_TERMS];
    for (uint term = RT_FIRST_TERM + program.lane; term < terms; term += program.lanes)
        count_discovered_term(term, false);
    step_program_end(program);
}
