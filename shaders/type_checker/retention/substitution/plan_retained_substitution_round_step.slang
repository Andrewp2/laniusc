// Substitution step 2 (one lane): plan the next round of step 3. One
// round of (plan, step) is an expansion round or an
// evaluation level, so expansion and evaluation share the rounds a batch
// records.
// - Expansion: the frontier is the tasks created since the last plan; the
//   round uses one lane per frontier task. An empty frontier ends expansion.
// - Evaluation: select the next nonempty level (empty levels cost no
//   round). No level left ends the attempt (SB_PHASE_DONE).
// Every other phase dispatches nothing.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;

uint plan_evaluation()
{
    if (rt_counts[RT_C_OVERFLOW] != 0u) sb_overflow(SB_OVERFLOW_STORE);
    if (sb_counts[SB_C_OVERFLOW] != 0u) { sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW; return 0u; }
    uint level = sb_counts[SB_C_LEVEL] + 1u;
    uint last = min(sb_counts[SB_C_MAX_LEVEL], SB_LEVELS - 1u);
    while (level <= last && sb_counts[SB_C_LEVEL_COUNT + level] == 0u) level++;
    if (level > last) { sb_counts[SB_C_PHASE] = SB_PHASE_DONE; return 0u; }
    sb_counts[SB_C_LEVEL] = level;
    sb_counts[SB_C_EVAL_ROUNDS] += 1u;
    uint lanes = min(sb_counts[SB_C_TASKS], sb_task_capacity());
    sb_counts[SB_C_EVAL_LANES] += lanes;
    return lanes;
}

uint plan_expansion()
{
    if (sb_counts[SB_C_OVERFLOW] != 0u) { sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW; return 0u; }
    uint lo = sb_counts[SB_C_FRONTIER_HI];
    uint hi = min(sb_counts[SB_C_TASKS], sb_task_capacity());
    uint arity = sb_counts[SB_C_NEXT_ARITY];
    sb_counts[SB_C_NEXT_ARITY] = 0u;
    if (hi <= lo)
    {
        sb_counts[SB_C_PHASE] = SB_PHASE_EVAL;
        return plan_evaluation();
    }
    uint round = sb_counts[SB_C_ROUNDS];
    if (round < SB_ROUND_LOG) sb_counts[SB_C_ROUND_LOG + round] = hi - lo;
    sb_counts[SB_C_ROUNDS] = round + 1u;
    sb_counts[SB_C_FRONTIER_LO] = lo;
    sb_counts[SB_C_FRONTIER_HI] = hi;
    sb_counts[SB_C_MAX_FRONTIER] = max(sb_counts[SB_C_MAX_FRONTIER], hi - lo);
    sb_counts[SB_C_MAX_ARITY] = max(sb_counts[SB_C_MAX_ARITY], arity);
    sb_counts[SB_C_EDGE_LANES] += hi - lo;
    return hi - lo;
}

public uint plan_retained_substitution_round()
{
    uint phase = sb_counts[SB_C_PHASE];
    if (phase == SB_PHASE_EXPAND) return plan_expansion();
    if (phase == SB_PHASE_EVAL) return plan_evaluation();
    return 0u;
}
