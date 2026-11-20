import codegen.x86.symbol_finalization.symbol_finalization_layout;
import codegen.x86.symbol_finalization.symbol_finalization_steps;
import codegen.x86.symbol_finalization.symbol_publication_predicate;
import shared.collectives.step_program;

struct Launch { uint groups; uint slot; uint options; uint reserved; };
ConstantBuffer<Launch> program_launch;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint symbols = gFinalize.symbol_count;
    uint words = gFinalize.identity_word_count;
    uint objects = gFinalize.object_count;
    for (uint row = program.lane; row < max(words, STATUS_WORDS); row += program.lanes)
        clear_finalize_row(row);
    if (!step_barrier(program)) return;

    // All three steps publish independent demand words or reduce failures by minimum.
    for (uint row = program.lane; row < objects; row += program.lanes)
        validate_object_range(row);
    if (program.lane == 0u) check_route_readiness();
    for (uint row = program.lane; row < symbols; row += program.lanes)
        claim_symbol_words(row);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < symbols; row += program.lanes)
        check_symbol_claims(row);
    if (!step_barrier(program)) return;

    if (finalize_publishable(fin_status))
    {
        if (program.lane == 0u) fin_status[STATUS_PUBLISHED] = gFinalize.generation;
        for (uint row = program.lane; row < symbols; row += program.lanes)
            publish_symbol(row);
        for (uint row = program.lane; row < words; row += program.lanes)
            publish_identity_word(row);
    }
    step_program_end(program);
}
