// Substitution step 5 (one lane): select the next nonempty level. Empty
// levels cost no dispatch round.
import type_checker.retention.substitution.sb_common;
import type_checker.retention.substitution.sb_dispatch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sb_set_dispatch(SB_D_EVAL, 0u);
    uint phase = sb_counts[SB_C_PHASE];
    if (phase == SB_PHASE_SCATTER)
    {
        sb_set_dispatch(SB_D_SCATTER, 0u);
        sb_counts[SB_C_PHASE] = SB_PHASE_EVAL;
        sb_counts[SB_C_LEVEL] = 0u;
        phase = SB_PHASE_EVAL;
    }
    if (phase != SB_PHASE_EVAL) return;
    if (sb_counts[SB_C_OVERFLOW] != 0u) { sb_counts[SB_C_PHASE] = SB_PHASE_OVERFLOW; return; }
    uint level = sb_counts[SB_C_LEVEL] + 1u;
    uint last = min(sb_counts[SB_C_MAX_LEVEL], SB_LEVELS - 1u);
    while (level <= last && sb_counts[SB_C_LEVEL_COUNT + level] == 0u) level++;
    if (level > last) { sb_counts[SB_C_PHASE] = SB_PHASE_DONE; return; }
    sb_counts[SB_C_LEVEL] = level;
    sb_counts[SB_C_EVAL_ROUNDS] += 1u;
    sb_counts[SB_C_EVAL_LANES] += sb_counts[SB_C_LEVEL_COUNT + level];
    sb_set_dispatch(SB_D_EVAL, sb_counts[SB_C_LEVEL_COUNT + level]);
}
