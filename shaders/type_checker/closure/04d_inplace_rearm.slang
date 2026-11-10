// An original job with in-place instantiations (inplace_read.slang) rewrote
// rows and constants that an earlier canonical stage interned, as a replay
// does: ask the next 03_rearm to re-arm every interned candidate. One lane,
// ahead of each rearm after the body passes (the stage's first round clears
// the request again).
import type_checker.canonical.canonical_api;

StructuredBuffer<uint> instance_inplace_counts;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || instance_inplace_counts[0u] == 0u) return;
    ct_counts[CT_COUNT_EARLY_REARM] = 1u;
}
