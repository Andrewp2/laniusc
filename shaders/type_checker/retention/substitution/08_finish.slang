// Substitution step 8 (one lane): close a finished attempt. A committed
// attempt publishes its state and keeps the terms it interned (they are
// complete, exactly interned records). An overflowed attempt records the
// store's overflow and demand for the host, restores the store's term
// counters, spare counters and status words to the watermark of step 0,
// and dispatches step 9 to clear the slots of the terms it interned.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;
import type_checker.retention.substitution.sb_dispatch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sb_set_dispatch(SB_D_ROLLBACK, 0u);
    uint phase = sb_counts[SB_C_PHASE];
    if (phase != SB_PHASE_DONE && phase != SB_PHASE_OVERFLOW) return;
    sb_counts[SB_C_STORE_OVERFLOW] = rt_counts[RT_C_OVERFLOW];
    sb_counts[SB_C_STORE_DEMAND_TERMS] = rt_counts[RT_C_DEMAND + RT_A_TERMS];
    sb_counts[SB_C_STORE_DEMAND_ARGS] = rt_counts[RT_C_DEMAND + RT_A_TERM_ARGS];
    if (phase == SB_PHASE_DONE && rt_counts[RT_C_OVERFLOW] == 0u)
    {
        sb_counts[SB_C_STORE_NEW_TERMS] = rt_counts[RT_A_TERMS] - sb_counts[SB_C_STORE_TERMS_BASE];
        rt_counts[RT_C_OVERFLOW] = sb_counts[SB_C_STORE_OVERFLOW_SAVED];
        sb_counts[SB_C_STATE] = SB_STATE_PUBLISHED;
        sb_counts[SB_C_PHASE] = SB_PHASE_FINAL;
        return;
    }
    if (rt_counts[RT_C_OVERFLOW] != 0u) sb_overflow(SB_OVERFLOW_STORE);
    rt_counts[RT_A_TERMS] = sb_counts[SB_C_STORE_TERMS_BASE];
    rt_counts[RT_A_TERM_ARGS] = sb_counts[SB_C_STORE_ARGS_BASE];
    rt_counts[RT_C_SPARE + RT_A_TERMS] = sb_counts[SB_C_STORE_SPARE_TERMS];
    rt_counts[RT_C_SPARE + RT_A_TERM_ARGS] = sb_counts[SB_C_STORE_SPARE_ARGS];
    rt_counts[RT_C_OVERFLOW] = sb_counts[SB_C_STORE_OVERFLOW_SAVED];
    rt_counts[RT_C_DEMAND + RT_A_TERMS] = sb_counts[SB_C_STORE_DEMAND_TERMS_SAVED];
    rt_counts[RT_C_DEMAND + RT_A_TERM_ARGS] = sb_counts[SB_C_STORE_DEMAND_ARGS_SAVED];
    sb_counts[SB_C_STATE] = SB_STATE_OVERFLOWED;
    sb_counts[SB_C_PHASE] = SB_PHASE_FINAL;
    uint slots; uint stride;
    rt_term_slot.GetDimensions(slots, stride);
    sb_set_dispatch(SB_D_ROLLBACK, slots);
}
