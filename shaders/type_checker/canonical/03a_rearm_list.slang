// Re-arm canonical interning for a stage's rounds (canonical_rearm.slang)
// and list the candidates left pending: round 0 of 01_intern interns only
// those (canonical_pending, counted in CT_COUNT_REARM_PENDING; 03b turns the
// count into round 0's dispatch).
//
// The list keeps the order round 0 swept the candidates in: constants
// first, then rows from the last, so leaves tend to publish before the rows
// that read them.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_rearm;

RWStructuredBuffer<uint> canonical_pending;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint count = ct_candidate_count();
    uint candidate = 0u;
    bool pending = false;
    if (i < count)
    {
        uint constants = count - ct_row_capacity();
        candidate = i < constants ? count - constants + i : count - 1u - i;
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
