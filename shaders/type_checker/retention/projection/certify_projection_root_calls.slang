import shared.collectives.step_program;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.certify_retained_native_abi_step;
import type_checker.retention.projection.finalize_retained_native_abi_step;

public bool certify_projection_root_calls(inout StepProgram program)
{
    uint calls; uint stride;
    nc_use_abi.GetDimensions(calls, stride);
    for (uint row = program.lane; row < min(calls / 2u, rt_counts[RT_A_USES]); row += program.lanes)
        certify_retained_native_abi(row);
    if (!step_barrier(program)) return false;
    if (program.lane == 0u) finalize_retained_native_abi();
    return true;
}
