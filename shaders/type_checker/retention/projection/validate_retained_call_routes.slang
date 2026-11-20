import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.validate_projection_call_routes;
import type_checker.retention.projection.certify_projection_root_calls;
import type_checker.retention.projection.write_projected_batch;

import type_checker.retention.projection.plan_retained_lowering_batches_step;

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
    if ((program_launch.options & 2u) != 0u)
    {
        if (!step_barrier(program)) return;
        uint batch = pj_config[PJ_CFG_BATCH] * PJ_BATCH_WORDS;
        write_projected_batch(program, projected_batch(
            pj_batches[batch], pj_batches[batch + 1u], pj_batches[batch + 2u]));
    }
    step_program_end(program);
}
