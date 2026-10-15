// Close one interning round (one lane). The frontier the round produced
// becomes the next round's input and its indirect dispatch arguments are
// written. A round that resolved nothing (a cycle) or the round limit makes
// the next round final, which turns every pending candidate into UNKNOWN.
import type_checker.canonical.canonical_api;

RWStructuredBuffer<uint> canonical_round_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint round = ct_counts[CT_COUNT_ROUND];
    uint produced = ct_counts[CT_COUNT_FRONTIER + ((round + 1u) & 1u)];
    uint consumed = ct_counts[CT_COUNT_PENDING];
    bool stalled = produced != 0u && produced == consumed;
    bool limit = produced != 0u && round + 2u >= CT_MAX_ROUNDS;
    if (stalled || limit) ct_counts[CT_COUNT_FINAL] = 1u;
    if (limit && !stalled) ct_counts[CT_COUNT_OVERFLOW] |= CT_OVERFLOW_ROUNDS;
    ct_counts[CT_COUNT_PENDING] = produced;
    // The next round appends to the list this round read.
    ct_counts[CT_COUNT_FRONTIER + (round & 1u)] = 0u;
    ct_counts[CT_COUNT_ROUND] = round + 1u;
    uint groups = (produced + 255u) / 256u;
    uint x = min(groups, 65535u);
    canonical_round_args[0u] = x;
    canonical_round_args[1u] = x == 0u ? 0u : (groups + 65534u) / 65535u;
    canonical_round_args[2u] = 1u;
}
