import shared.collectives.step_program;
import type_checker.retention.substitution.retained_substitution_workspace;

public void reset_retained_substitution(StepProgram program)
{
    uint slots; uint stride;
    sb_memo.GetDimensions(slots, stride);
    SbMemoEntry empty = { 0u, 0u, 0u };
    for (uint row = program.lane; row < slots; row += program.lanes)
        sb_memo[row] = empty;
    sb_term_slots.GetDimensions(slots, stride);
    for (uint row = program.lane; row < slots; row += program.lanes)
        sb_term_slots[row] = uint2(0u);
    for (uint row = program.lane; row < SB_C_SYNC_FAILED; row += program.lanes)
        sb_counts[row] = 0u;
}
