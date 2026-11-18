// Appends a wave's pending candidates to canonical_pending, counted in
// CT_COUNT_REARM_PENDING (03a_rearm_list, 03c_rearm_live_list). Every lane
// of the wave calls it.
void rearm_list_append(uint candidate, bool pending)
{
    uint lanes = WaveActiveCountBits(pending);
    uint base = 0u;
    if (WaveIsFirstLane() && lanes != 0u)
        InterlockedAdd(ct_counts[CT_COUNT_REARM_PENDING], lanes, base);
    base = WaveReadLaneFirst(base);
    if (pending)
    {
        uint slot = base + WavePrefixCountBits(pending);
        uint capacity; uint stride;
        canonical_pending.GetDimensions(capacity, stride);
        if (slot < capacity) canonical_pending[slot] = candidate;
    }
}
