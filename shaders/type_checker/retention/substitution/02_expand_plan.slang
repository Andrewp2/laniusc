// Substitution step 2 (one lane): plan the next expansion round. The
// frontier is the tasks created since the last plan; a round dispatches one
// lane per (frontier task, child index below the frontier's largest arity).
// An empty frontier ends expansion: the level buckets get their bases and
// the scatter is dispatched over every task.
import type_checker.retention.substitution.sb_common;
import type_checker.retention.substitution.sb_dispatch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sb_set_dispatch(SB_D_EXPAND, 0u);
    if (sb_counts[SB_C_PHASE] != SB_PHASE_EXPAND) return;
    if (sb_counts[SB_C_OVERFLOW] != 0u) { sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW; return; }
    uint lo = sb_counts[SB_C_FRONTIER_HI];
    uint hi = min(sb_counts[SB_C_TASKS], sb_task_capacity());
    uint arity = sb_counts[SB_C_NEXT_ARITY];
    sb_counts[SB_C_NEXT_ARITY] = 0u;
    if (hi <= lo)
    {
        uint base = 0u;
        for (uint level = 0u; level < SB_LEVELS; level++)
        {
            sb_counts[SB_C_LEVEL_BASE + level] = base;
            sb_counts[SB_C_LEVEL_CURSOR + level] = 0u;
            base += sb_counts[SB_C_LEVEL_COUNT + level];
        }
        sb_counts[SB_C_PHASE] = SB_PHASE_SCATTER;
        sb_set_dispatch(SB_D_SCATTER, hi);
        return;
    }
    uint round = sb_counts[SB_C_ROUNDS];
    if (round < SB_ROUND_LOG) sb_counts[SB_C_ROUND_LOG + round] = hi - lo;
    sb_counts[SB_C_ROUNDS] = round + 1u;
    sb_counts[SB_C_FRONTIER_LO] = lo;
    sb_counts[SB_C_FRONTIER_HI] = hi;
    sb_counts[SB_C_FRONTIER_ARITY] = arity;
    sb_counts[SB_C_MAX_FRONTIER] = max(sb_counts[SB_C_MAX_FRONTIER], hi - lo);
    sb_counts[SB_C_MAX_ARITY] = max(sb_counts[SB_C_MAX_ARITY], arity);
    // Lane numbers are 32-bit: a wider round cannot be dispatched. The
    // product is checked in 16-bit halves (arity is at most 64).
    uint width = hi - lo;
    uint upper = (width >> 16u) * arity;
    uint lower = (width & 0xffffu) * arity;
    if (upper >= 0x10000u || (upper << 16u) > ~lower)
    {
        sb_overflow(SB_OVERFLOW_LANES);
        sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW;
        return;
    }
    uint lanes = (hi - lo) * arity;
    sb_counts[SB_C_EDGE_LANES] += lanes;
    sb_set_dispatch(SB_D_EXPAND, lanes);
}
