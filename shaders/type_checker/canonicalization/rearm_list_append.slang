// Appends a wave's pending candidates to canonical_pending, counted in
// CT_COUNT_REARM_PENDING (list_canonical_candidates_to_rearm, list_live_canonical_candidates_to_rearm). Every lane
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
