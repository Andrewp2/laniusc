import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.resolve_discovery_requests_step;
import type_checker.retention.discovery.discovery_request_status;
import type_checker.retention.substitution.retained_substitution_results;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (dg_status[28] != 0u)
    {
        if (program.leader)
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u);
        return;
    }
    uint requests = max(1u, sb_counts[SB_C_REQUESTS]);
    for (uint row = program.lane; row < requests; row += program.lanes)
        resolve_discovery_requests(row);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) finish_discovery_requests();
    step_program_end(program);
}
