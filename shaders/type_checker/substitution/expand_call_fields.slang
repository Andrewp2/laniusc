import type_checker.calls.inference_program;
import shared.collectives.step_program;
import type_checker.substitution.call_field_closure_roots;
import type_checker.substitution.field_closure;
import type_checker.substitution.field_closure_steps;
import type_checker.substitution.field_closure_progress;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = begin_call_inference_program(group, local);
    ct_expand_begin_run(program.lane, 1u);
    uint deferred = ct_expand_counts[CT_EXPAND_DEFERRED];
    for (uint row = program.lane; row < deferred; row += program.lanes)
        requeue_call_field_closure_root(row, status);
    uint roots = call_field_closure_root_count();
    for (uint row = program.lane; row < roots; row += program.lanes)
        queue_call_field_closure_root(row, status);
    if (!call_inference_barrier(program, status)) return;

    if (program.lane == 0u)
    {
        if (ct_expand_run_empty()) ct_expand_close_empty_run();
        else advance_field_closure();
    }
    if (!call_inference_barrier(program, status)) return;

    // Let one lane per wave expand an entry, as in the standalone level pass.
    for (uint level = 0u; level < CT_EXPAND_LEVELS_PER_RUN; ++level)
    {
        if (ct_expand_counts[CT_EXPAND_ROUND] == 0u) break;
        uint first = ct_expand_counts[CT_EXPAND_START];
        uint end = ct_expand_counts[CT_EXPAND_END];
        // An empty level cannot queue more entries. The remaining advances
        // would leave START = END and close the run without reporting progress.
        if (first == end)
        {
            if (program.lane == 0u) ct_expand_close_empty_run();
            break;
        }
        if (program.lane % CT_EXPAND_LANES_PER_ENTRY == 0u)
        {
            for (uint row = first + program.lane / CT_EXPAND_LANES_PER_ENTRY;
                 row < end; row += program.lanes / CT_EXPAND_LANES_PER_ENTRY)
                expand_field_closure_entry(row);
        }
        if (!call_inference_barrier(program, status)) return;
        if (program.lane == 0u) advance_field_closure();
        if (level + 1u < CT_EXPAND_LEVELS_PER_RUN &&
            !call_inference_barrier(program, status)) return;
    }

    step_program_end(program);
}
