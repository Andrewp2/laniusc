import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.begin_retained_substitution_step;
import type_checker.retention.substitution.admit_retained_substitution_roots_step;
import type_checker.retention.substitution.plan_retained_substitution_round_step;
import type_checker.retention.substitution.process_retained_substitution_tasks_step;
import type_checker.retention.substitution.publish_retained_substitution_results_step;
import type_checker.retention.substitution.finalize_retained_substitution_step;
import type_checker.retention.substitution.roll_back_retained_substitution_step;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (sb_counts[SB_C_SYNC_FAILED] != 0u)
    {
        // The readback after a chain must see a failure from any of its runs.
        if (program.leader)
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u);
        return;
    }

    if ((program_launch.options & 1u) != 0u)
    {
        if (program.lane == 0u) begin_retained_substitution();
        if (!step_barrier(program)) return;
        uint requests = sb_request_total();
        for (uint row = program.lane; row < requests; row += program.lanes)
            admit_retained_substitution_roots(row);
        if (!step_barrier(program)) return;
    }

    uint rounds = program_launch.options >> 1u;
    uint phase = 0u;
    for (uint round = 0u; round < rounds; ++round)
    {
        if (program.lane == 0u) sb_counts[SB_C_ROUND_LANES] = plan_retained_substitution_round();
        if (!step_barrier(program)) return;
        phase = sb_counts[SB_C_PHASE];
        if (phase >= SB_PHASE_DONE) break;
        uint lanes = sb_counts[SB_C_ROUND_LANES];
        for (uint row = program.lane; row < lanes; row += program.lanes)
            process_retained_substitution_tasks(row, phase);
        if (!step_barrier(program)) return;
    }

    if (phase == SB_PHASE_DONE || phase == SB_PHASE_OVERFLOW)
    {
        uint requests = sb_request_total();
        for (uint row = program.lane; row < requests; row += program.lanes)
            publish_retained_substitution_results(row);
        if (!step_barrier(program)) return;
        if (program.lane == 0u) finalize_retained_substitution();
        if (!step_barrier(program)) return;
        if (sb_counts[SB_C_STATE] == SB_STATE_OVERFLOWED)
        {
            uint slots; uint stride;
            rt_term_slot.GetDimensions(slots, stride);
            for (uint row = program.lane; row < slots; row += program.lanes)
                roll_back_retained_substitution(row);
        }
    }
    step_program_end(program);
}
