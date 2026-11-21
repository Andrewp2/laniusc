import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_rank_order;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    if (dg_status[10u] != 0u) return;
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = dg_config[13];
    uint instances = dg_status[0];
    for (uint row = program.lane; row < rows; row += program.lanes)
        dg_order[row] = row < instances && dg_instances[2u * row].x != 0u ? row : RT_INVALID;
    if (!step_barrier(program)) return;
    if (!sort_discovery_order(program, InstanceOrder(), rows)) return;

    uint live = dg_status[1];
    for (uint row = program.lane; row < live; row += program.lanes)
        dg_rank[dg_order[row]] = row;
    step_program_end(program);
}
