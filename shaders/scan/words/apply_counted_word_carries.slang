// Apply of a GPU-counted u32 exclusive scan (counted_word_carries.slang).

#include "counted_word_carries.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    counted_apply(gid, ltid);
}
