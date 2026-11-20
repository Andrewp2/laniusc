import codegen.lir.x86.emission.artifact_layout_steps;
import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct Launch { uint groups; uint slot; uint is_object; uint reserved; };
ConstantBuffer<Launch> program_launch;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = min(gParams.target_capacity, target_lir_total[0u]);
    if (program.lane == 0u) clear_entrypoint();
    if (!step_program_prefix_scan(program, rows, target_byte_length,
            target_byte_offset, x86_body_length, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint functions = min(gParams.function_capacity, semantic_lir_function_total[0u]);
    for (uint row = program.lane; row < functions; row += program.lanes)
        select_entrypoint(row);
    if (!step_barrier(program)) return;

    if (program.lane == 0u)
    {
        plan_layout();
        if (program_launch.is_object != 0u) normalize_object_status();
    }
    step_program_end(program);
}
