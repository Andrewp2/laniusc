import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.certify_retained_native_abi_step;
import type_checker.retention.projection.finalize_retained_native_abi_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint calls; uint stride;
    nc_use_abi.GetDimensions(calls, stride);
    for (uint row = program.lane; row < min(calls / 2u, rt_counts[RT_A_USES]); row += program.lanes)
        certify_retained_native_abi(row);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) finalize_retained_native_abi();
    step_program_end(program);
}
