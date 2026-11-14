// Substitution step 3: one lane per (frontier task, child index). Resolves
// the child under the task's environment and writes the task's edge: an
// immediate value or failure, or the child's (possibly new) task. Each lane
// handles exactly one edge (and compares its argument with the earlier
// ones, at most 63); new tasks form the next frontier.
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = sb_lane(dtid);
    uint arity_stride = sb_counts[SB_C_FRONTIER_ARITY];
    if (arity_stride == 0u) return;
    uint task = sb_counts[SB_C_FRONTIER_LO] + lane / arity_stride;
    uint index = lane % arity_stride;
    if (task >= sb_counts[SB_C_FRONTIER_HI]) return;
    uint4 key = sb_task_key[task];
    if ((key.z & SB_DEAD) != 0u) return;
    if (index >= rt_term_arity(key.y)) return;
    // A repeated argument (Pair<D, D>) shares the first occurrence's edge,
    // so two lanes of one task never race to create one child task.
    uint child = rt_term_arg(key.y, index);
    for (uint j = 0u; j < index; j++)
    {
        if (rt_term_arg(key.y, j) == child)
        {
            sb_edges[key.w + index] = uint2(j, SB_EDGE_SAME);
            return;
        }
    }
    SbBinder b = sb_binder(key.x);
    sb_edges[key.w + index] = sb_edge(sb_resolve(b, child));
    InterlockedAdd(sb_counts[SB_C_EDGES_RESOLVED], 1u);
}
