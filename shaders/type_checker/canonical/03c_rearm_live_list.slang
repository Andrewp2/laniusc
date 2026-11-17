// The re-arm list of the stages after the early one: 03a_rearm_list over
// the allocated candidates only (canonical_live_rearm), in the same order.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_rearm;

RWStructuredBuffer<uint> canonical_pending;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    LiveRearm live = canonical_live_rearm();
    uint candidate = 0u;
    bool pending = false;
    if (i < canonical_live_rearm_count(live))
    {
        candidate = canonical_live_rearm_candidate(live, i);
        pending = canonical_rearm_candidate(candidate);
    }
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
    if (i == 0u) canonical_rearm_reset_rounds();
}
