// Apply of two independent counted scans (apply_body.slang).

#include "apply_body.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    counted_pair_apply(gid, ltid);
}
