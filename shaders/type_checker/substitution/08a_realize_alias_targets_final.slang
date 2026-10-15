// The last realization dispatch of the imported alias targets
// (realize_alias_targets.slang): a target that still meets a row another
// lane is writing is reported.
#include "realize_alias_targets.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    realize_alias_target(dtid.x + dtid.y * 16776960u, true);
}
