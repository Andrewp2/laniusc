// Apply of two independent counted scans (counted_pair_carries.slang).

#include "counted_pair_carries.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    counted_pair_apply(gid, ltid);
}
