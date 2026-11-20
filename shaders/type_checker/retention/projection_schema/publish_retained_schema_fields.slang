import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.projection_schema.advance_retained_schema_round_step;
import type_checker.retention.projection_schema.publish_projected_schema_field_types_step;

import type_checker.retention.substitution.retained_substitution_results;
StructuredBuffer<uint> sb_request_count;

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

    uint requests = sb_request_count[0u];
    uint run = ps_config[PS_CFG_RUN];
    for (uint row = program.lane; row < requests; row += program.lanes)
        publish_projected_schema_field_types(row, sb_results[row * SB_RESULT_WORDS], sb_result_current(run, row));
    if (program_launch.options != 0u)
    {
        if (!step_barrier(program)) return;
        if (program.lane == 0u) advance_retained_schema_round(1u, run, sb_publication_current(run), sb_counts[SB_C_SYNC_FAILED] != 0u);
    }

    step_program_end(program);
}
