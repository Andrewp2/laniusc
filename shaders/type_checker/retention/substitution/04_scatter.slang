// Substitution step 4: one lane per task. Places each live task in its
// level's block of sb_order.
import type_checker.retention.substitution.sb_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint task = sb_lane(dtid);
    if (sb_counts[SB_C_PHASE] != SB_PHASE_SCATTER) return;
    if (task >= min(sb_counts[SB_C_TASKS], sb_task_capacity())) return;
    uint level = sb_task_key[task].z;
    if ((level & SB_DEAD) != 0u) return;
    uint at;
    InterlockedAdd(sb_counts[SB_C_LEVEL_CURSOR + level], 1u, at);
    sb_order[sb_counts[SB_C_LEVEL_BASE + level] + at] = task;
}
