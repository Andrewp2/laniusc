// Round 0's dispatch over the candidates 03a_rearm_list left pending (one
// lane). The count becomes the round's input (CT_COUNT_PENDING) and the list
// counter starts the next stage at zero. The early stage's re-arm has read
// CT_COUNT_EARLY_REARM; the later ones must not.
import type_checker.canonical.canonical_api;

RWStructuredBuffer<uint> canonical_round_args;
StructuredBuffer<uint> canonical_pending;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint capacity; uint stride;
    canonical_pending.GetDimensions(capacity, stride);
    uint pending = min(ct_counts[CT_COUNT_REARM_PENDING], capacity);
    ct_counts[CT_COUNT_REARM_PENDING] = 0u;
    ct_counts[CT_COUNT_PENDING] = pending;
    ct_counts[CT_COUNT_EARLY_REARM] = 0u;
    uint groups = (pending + 255u) / 256u;
    uint x = min(groups, 65535u);
    canonical_round_args[0u] = x;
    canonical_round_args[1u] = x == 0u ? 0u : (groups + 65534u) / 65535u;
    canonical_round_args[2u] = 1u;
}
