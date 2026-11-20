// Substitution step 6: one lane per store term slot of an overflowed
// attempt. Clears every slot that points at a term the attempt allocated.
// Linear probing stays sound: every key inserted before the attempt
// stopped at a slot that was occupied then.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;

public void roll_back_retained_substitution(uint slot)
{
    if (sb_counts[SB_C_STATE] != SB_STATE_OVERFLOWED) return;
    uint slots; uint stride;
    rt_term_slot.GetDimensions(slots, stride);
    if (slot < slots && rt_term_slot[slot] >= sb_counts[SB_C_STORE_TERMS_BASE]) rt_term_slot[slot] = 0u;
}
