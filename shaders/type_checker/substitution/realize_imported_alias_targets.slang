// A retrying realization dispatch of the imported alias targets
// (imported_alias_realization.slang): a target that meets a row another lane is
// writing stays pending for the next dispatch.
#include "imported_alias_realization.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    realize_alias_target(dtid.x + dtid.y * 16776960u, false);
}
