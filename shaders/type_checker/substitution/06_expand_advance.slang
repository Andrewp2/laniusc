// Close one field-closure level round (one lane): the entries the previous
// round queued become this round's input, and the level kernel's indirect
// dispatch arguments are written. The last advance of a run dispatches no
// level; inside the inference rounds it reports queued leftovers as
// progress, so the next inference round continues the closure.
import type_checker.substitution.ct_expand;

RWStructuredBuffer<uint> ct_expand_args;
RWStructuredBuffer<uint> call_inference_state;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint capacity; uint stride;
    ct_expand_queue.GetDimensions(capacity, stride);
    uint length = min(ct_expand_counts[CT_EXPAND_LENGTH], capacity);
    uint round = ct_expand_counts[CT_EXPAND_ROUND] % (CT_EXPAND_LEVELS_PER_RUN + 1u);
    ct_expand_counts[CT_EXPAND_ROUND] = (round + 1u) % (CT_EXPAND_LEVELS_PER_RUN + 1u);
    uint groups = 0u;
    if (round < CT_EXPAND_LEVELS_PER_RUN)
    {
        uint start = ct_expand_counts[CT_EXPAND_END];
        ct_expand_counts[CT_EXPAND_START] = start;
        ct_expand_counts[CT_EXPAND_END] = length;
        groups = (length - start + 255u) / 256u;
    }
    else if (length > ct_expand_counts[CT_EXPAND_END] && ct_expand_counts[CT_EXPAND_MODE] != 0u)
    {
        uint ignored;
        InterlockedAdd(call_inference_state[1u], 1u, ignored);
    }
    uint x = min(groups, 65535u);
    ct_expand_args[0u] = x;
    ct_expand_args[1u] = x == 0u ? 0u : (groups + 65534u) / 65535u;
    ct_expand_args[2u] = 1u;
}
