// Apply of a GPU-counted u32 exclusive scan that also writes the indirect
// dispatch arguments for its total (apply_body.slang).

#define SCAN_TOTAL_DISPATCH
#include "apply_body.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    counted_apply(gid, ltid);
}
