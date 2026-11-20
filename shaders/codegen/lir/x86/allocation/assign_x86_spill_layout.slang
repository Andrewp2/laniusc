import codegen.lir.x86.allocation.spill_layout_steps;
import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct Launch { uint groups; uint slot; uint options; uint reserved; };
ConstantBuffer<Launch> program_launch;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint locals = min(place_params.local_capacity, semantic_lir_local_total[0u]);
    uint nodes = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint functions = min(gParams.function_capacity, semantic_lir_function_total[0u]);

    for (uint row = program.lane; row < locals; row += program.lanes)
        count_local_words(row);
    if (!step_program_prefix_scan(program, nodes, x86_stack_words_by_position,
            x86_stack_prefix_by_position, x86_stack_word_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < nodes; row += program.lanes)
        place_spill(row, nodes);
    for (uint row = program.lane; row < functions; row += program.lanes)
        summarize_spills(row);
    if (!step_program_prefix_scan(program, locals, x86_place_words_by_local,
            x86_place_prefix_by_local, x86_place_word_total, scan_group_sums)) return;
    step_program_end(program);
}
