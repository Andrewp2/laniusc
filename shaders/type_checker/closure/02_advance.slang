// Close one instance-closure round (one lane): the instances the previous
// round appended become this round's frontier, and 03_expand's indirect
// dispatch arguments are written. After IC_LEVELS rounds the closing
// advance dispatches nothing and flags a frontier it leaves unexpanded.
import type_checker.closure.instance_closure;

RWStructuredBuffer<uint> instance_closure_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint length = min(instance_closure_counts[IC_COUNT_LENGTH], ic_instance_capacity());
    uint round = instance_closure_counts[IC_COUNT_ROUND];
    instance_closure_counts[IC_COUNT_ROUND] = round + 1u;
    uint start = instance_closure_counts[IC_COUNT_END];
    uint groups = 0u;
    if (round < IC_LEVELS)
    {
        instance_closure_counts[IC_COUNT_START] = start;
        instance_closure_counts[IC_COUNT_END] = length;
        groups = (length - start + 255u) / 256u;
    }
    else if (length > start)
    {
        ic_flag(IC_FLAG_DEPTH);
    }
    uint x = min(groups, 65535u);
    instance_closure_args[0u] = x;
    instance_closure_args[1u] = x == 0u ? 0u : (groups + 65534u) / 65535u;
    instance_closure_args[2u] = 1u;
}
