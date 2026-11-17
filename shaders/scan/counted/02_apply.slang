// Apply of a GPU-counted u32 exclusive scan (apply_body.slang).

#include "apply_body.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    counted_apply(gid, ltid);
}
