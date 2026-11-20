import codegen.lir.x86.objects.object_record_steps;
import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct Launch { uint groups; uint slot; uint options; uint reserved; };
ConstantBuffer<Launch> program_launch;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint nodes = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint functions = min(gParams.function_capacity, semantic_lir_function_total[0u]);
    uint target_functions = min(gParams.function_capacity, target_function_count[0u]);
    uint target_rows = min(gParams.target_capacity, target_lir_total[0u]);

    for (uint row = program.lane; row < nodes; row += program.lanes)
        mark_relocations(row);
    for (uint row = program.lane; row < functions; row += program.lanes)
        mark_definitions(row, target_functions);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, nodes, x86_object_relocation_flag,
            x86_object_relocation_prefix, x86_object_relocation_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, nodes, x86_object_symbol_flag,
            x86_object_symbol_prefix, x86_object_symbol_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, functions, x86_object_definition_flag,
            x86_object_definition_prefix, x86_object_definition_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, target_rows, x86_runtime_reference_flag,
            x86_runtime_relocation_prefix, x86_object_runtime_relocation_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < nodes; row += program.lanes)
        write_relocations(row, target_rows, target_functions);
    for (uint row = program.lane; row < target_rows; row += program.lanes)
        write_runtime_relocations(row);
    for (uint row = program.lane; row < functions; row += program.lanes)
        write_definitions(row, target_functions);
    step_program_end(program);
}
