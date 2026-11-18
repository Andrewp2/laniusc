// The latest token-context event before a token block: the maximum of the
// block events (`statement_event_block`) of the blocks before it. Each apply
// workgroup reduces them itself, so no scan dispatch runs between a context
// pass's local and apply kernels. The maximum does not depend on the order
// of the reduction. Every lane of the workgroup must call this.

groupshared uint context_event_before_block_max;

public uint context_event_before_block(
    StructuredBuffer<uint> block_events,
    uint block,
    uint lane,
    uint workgroup_size)
{
    if (lane == 0u)
        context_event_before_block_max = 0u;
    GroupMemoryBarrierWithGroupSync();
    uint before = 0u;
    for (uint i = lane; i < block; i += workgroup_size)
        before = max(before, block_events[i]);
    before = WaveActiveMax(before);
    if (WaveIsFirstLane())
        InterlockedMax(context_event_before_block_max, before);
    GroupMemoryBarrierWithGroupSync();
    return context_event_before_block_max;
}
