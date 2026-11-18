// Phase-specific predicate-obligation validation entry point. This pass only
// reads the count and scanned-prefix products emitted by preceding graph passes.
#define LANIUS_OBLIGATION_VALIDATE_PASS 1
#include "predicate_obligation_checks.slang"

// Lanes per obligation pair; only the first of them validates it. A pair
// walks contracts, hashes keys and matches impls on paths that differ from
// pair to pair, and a wave runs its lanes' paths one after another, so one
// pair per wave finishes sooner. The dispatch arguments multiply the pair
// total by the same count (bind_support/predicates.rs).
static const uint OBLIGATION_PAIR_LANES = 32u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = linear_thread_id(dtid);
    if (lane % OBLIGATION_PAIR_LANES != 0u) return;
    validate_call_predicate_obligation_pair(lane / OBLIGATION_PAIR_LANES);
}
