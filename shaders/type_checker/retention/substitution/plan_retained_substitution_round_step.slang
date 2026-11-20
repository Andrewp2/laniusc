// Substitution step 2 (one lane): plan the next round of step 3. One
// round of (plan, step) is an expansion round, the scatter or an
// evaluation level, so expansion and evaluation share the rounds a batch
// records.
// - Expansion: the frontier is the tasks created since the last plan; the
//   round dispatches one lane per (frontier task, child index below the
//   frontier's largest arity). An empty frontier ends expansion: the level
//   buckets get their bases and the scatter is dispatched over every task.
// - Evaluation: select the next nonempty level (empty levels cost no
//   round). No level left ends the attempt (SB_PHASE_DONE).
// Every other phase dispatches nothing.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;

uint plan_expansion()
{
    if (sb_counts[SB_C_OVERFLOW] != 0u) { sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW; return 0u; }
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
        return hi;
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
        return 0u;
    }
    uint lanes = (hi - lo) * arity;
    sb_counts[SB_C_EDGE_LANES] += lanes;
    return lanes;
}

uint plan_evaluation()
{
    uint phase = sb_counts[SB_C_PHASE];
    if (phase == SB_PHASE_SCATTER)
    {
        sb_counts[SB_C_PHASE] = SB_PHASE_EVAL;
        sb_counts[SB_C_LEVEL] = 0u;
        phase = SB_PHASE_EVAL;
    }
    if (phase != SB_PHASE_EVAL) return 0u;
    if (rt_counts[RT_C_OVERFLOW] != 0u) sb_overflow(SB_OVERFLOW_STORE);
    if (sb_counts[SB_C_OVERFLOW] != 0u) { sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW; return 0u; }
    uint level = sb_counts[SB_C_LEVEL] + 1u;
    uint last = min(sb_counts[SB_C_MAX_LEVEL], SB_LEVELS - 1u);
    while (level <= last && sb_counts[SB_C_LEVEL_COUNT + level] == 0u) level++;
    if (level > last) { sb_counts[SB_C_PHASE] = SB_PHASE_DONE; return 0u; }
    sb_counts[SB_C_LEVEL] = level;
    sb_counts[SB_C_EVAL_ROUNDS] += 1u;
    sb_counts[SB_C_EVAL_LANES] += sb_counts[SB_C_LEVEL_COUNT + level];
    return sb_counts[SB_C_LEVEL_COUNT + level];
}

public uint plan_retained_substitution_round()
{
    uint phase = sb_counts[SB_C_PHASE];
    if (phase == SB_PHASE_EXPAND) return plan_expansion();
    if (phase == SB_PHASE_SCATTER || phase == SB_PHASE_EVAL) return plan_evaluation();
    return 0u;
}
