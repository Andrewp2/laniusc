import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.normalization.proof_normalization_stages;
import type_checker.trait_solver.proof_frontier.proof_work;
import shared.collectives.step_program;

struct Launch
{
    uint groups;
    uint slot;
    uint options;
    uint reserved;
};
ConstantBuffer<Launch> program_launch;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    // The planner places the new Work span in the unused sidecar words,
    // adding one to its count when the program is active.
    if (trait_solver_params.recipe_word_count == 0u) return;

    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = trait_solver_params.dispatch_count;
    for (uint row = program.lane; row < rows; row += program.lanes)
        pps_stage_audit_normalized_goals(row);
    if (!step_barrier(program)) return;

    if (program.lane == 0u) pps_stage_commit_normalized_goals();
    if (!step_barrier(program)) return;

    uint first = trait_solver_params.work_word_count;
    uint count = trait_solver_params.recipe_word_count - 1u;
    for (uint row = program.lane; row < rows; row += program.lanes)
    {
        pps_stage_mark_normalized_goals(row);
        uint work = trait_solver_params.dispatch_first + row;
        // Index insertion reads only its own Work key and the admitted goal.
        if (work >= first && work - first < count && pps_building() && ts_batch_is_building())
            ts_batch_failure(pps_insert_work(work));
    }
    step_program_end(program);
}
