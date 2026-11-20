// Substitution step 5 (one lane): close a finished attempt. Both outcomes
// record the store's overflow and demand for the host, then restore the
// store's overflow and term demand words saved by step 0.
// - A committed attempt publishes its state and keeps the terms it
//   interned (they are complete, exactly interned records).
// - An overflowed attempt also restores the store's term counters and spare
//   counters to the watermark of step 0, counts the store terms it interned
//   (SB_C_STORE_ROLLED_BACK), and dispatches step 6 to clear their slots.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;

public void finalize_retained_substitution()
{
    uint phase = sb_counts[SB_C_PHASE];
    if (phase != SB_PHASE_DONE && phase != SB_PHASE_OVERFLOW) return;
    uint store_overflow = rt_counts[RT_C_OVERFLOW];
    sb_counts[SB_C_STORE_OVERFLOW] = store_overflow;
    sb_counts[SB_C_STORE_DEMAND_TERMS] = rt_counts[RT_C_DEMAND + RT_A_TERMS];
    sb_counts[SB_C_STORE_DEMAND_ARGS] = rt_counts[RT_C_DEMAND + RT_A_TERM_ARGS];
    rt_counts[RT_C_OVERFLOW] = sb_counts[SB_C_STORE_OVERFLOW_SAVED];
    rt_counts[RT_C_DEMAND + RT_A_TERMS] = sb_counts[SB_C_STORE_DEMAND_TERMS_SAVED];
    rt_counts[RT_C_DEMAND + RT_A_TERM_ARGS] = sb_counts[SB_C_STORE_DEMAND_ARGS_SAVED];
    uint base = sb_counts[SB_C_STORE_TERMS_BASE];
    if (phase == SB_PHASE_DONE && store_overflow == 0u)
    {
        sb_counts[SB_C_STORE_NEW_TERMS] = rt_counts[RT_A_TERMS] - base;
        sb_counts[SB_C_STATE] = SB_STATE_PUBLISHED;
        sb_counts[SB_C_PHASE] = SB_PHASE_FINAL;
        return;
    }
    if (store_overflow != 0u) sb_overflow(SB_OVERFLOW_STORE);
    // The counter keeps the requested end of failed allocations; only
    // records below the capacity were written.
    sb_counts[SB_C_STORE_ROLLED_BACK] = min(rt_counts[RT_A_TERMS], rt_capacity(RT_A_TERMS)) - min(base, rt_capacity(RT_A_TERMS));
    rt_counts[RT_A_TERMS] = base;
    rt_counts[RT_A_TERM_ARGS] = sb_counts[SB_C_STORE_ARGS_BASE];
    rt_counts[RT_C_SPARE + RT_A_TERMS] = sb_counts[SB_C_STORE_SPARE_TERMS];
    rt_counts[RT_C_SPARE + RT_A_TERM_ARGS] = sb_counts[SB_C_STORE_SPARE_ARGS];
    sb_counts[SB_C_STATE] = SB_STATE_OVERFLOWED;
    sb_counts[SB_C_PHASE] = SB_PHASE_FINAL;
}
