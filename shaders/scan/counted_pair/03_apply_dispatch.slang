// Apply of two counted scans that also writes the indirect dispatch
// arguments for both totals (apply_body.slang).

#define SCAN_TOTAL_DISPATCH
#include "apply_body.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    counted_pair_apply(gid, ltid);
}
