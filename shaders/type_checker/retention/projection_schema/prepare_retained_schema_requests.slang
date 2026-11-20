import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.projection_schema.prepare_schema_round_requests;

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

    if (!prepare_schema_round_requests(program, true)) return;
    step_program_end(program);
}
