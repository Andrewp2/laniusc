import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.write_projected_batch;

StructuredBuffer<uint4> pj_batches;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint batch = pj_config[PJ_CFG_BATCH] * PJ_BATCH_WORDS;
    write_projected_batch(program, projected_batch(
        pj_batches[batch], pj_batches[batch + 1u], pj_batches[batch + 2u]));
    step_program_end(program);
}
