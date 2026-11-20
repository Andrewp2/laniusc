import shared.collectives.step_program;
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.begin_retained_substitution_step;
import type_checker.retention.substitution.admit_retained_substitution_roots_step;
import type_checker.retention.substitution.plan_retained_substitution_round_step;
import type_checker.retention.substitution.process_retained_substitution_tasks_step;
import type_checker.retention.substitution.publish_retained_substitution_results_step;
import type_checker.retention.substitution.finalize_retained_substitution_step;
import type_checker.retention.substitution.roll_back_retained_substitution_step;


public interface ISubstitutionRequests
{
    uint count();
    uint capacity();
    uint4 request(uint row);
}

public bool run_retained_substitution<R : ISubstitutionRequests>(
    inout StepProgram program, uint options, R source)
{
    if (sb_counts[SB_C_SYNC_FAILED] != 0u)
    {
        // The readback after a chain must see a failure from any of its runs.
        if (program.leader)
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u);
        return false;
    }

    if ((options & 1u) != 0u)
    {
        if (program.lane == 0u) begin_retained_substitution(source.count(), source.capacity());
        if (!step_barrier(program)) return false;
        uint requests = sb_request_total();
        for (uint row = program.lane; row < requests; row += program.lanes)
            admit_retained_substitution_roots(row, source.request(row));
        if (!step_barrier(program)) return false;
    }

    uint rounds = options >> 1u;
    uint phase = 0u;
    for (uint round = 0u; round < rounds; ++round)
    {
        if (program.lane == 0u) sb_counts[SB_C_ROUND_LANES] = plan_retained_substitution_round();
        if (!step_barrier(program)) return false;
        phase = sb_counts[SB_C_PHASE];
        if (phase >= SB_PHASE_DONE) break;
        uint lanes = sb_counts[SB_C_ROUND_LANES];
        for (uint row = program.lane; row < lanes; row += program.lanes)
            process_retained_substitution_tasks(row, phase);
        if (!step_barrier(program)) return false;
    }

    if (phase == SB_PHASE_DONE || phase == SB_PHASE_OVERFLOW)
    {
        uint requests = sb_request_total();
        for (uint row = program.lane; row < requests; row += program.lanes)
            publish_retained_substitution_results(row, source.request(row));
        if (!step_barrier(program)) return false;
        if (program.lane == 0u) finalize_retained_substitution();
        if (!step_barrier(program)) return false;
        if (sb_counts[SB_C_STATE] == SB_STATE_OVERFLOWED)
        {
            uint slots; uint stride;
            rt_term_slot.GetDimensions(slots, stride);
            for (uint row = program.lane; row < slots; row += program.lanes)
                roll_back_retained_substitution(row);
        }
    }
    return true;
}
