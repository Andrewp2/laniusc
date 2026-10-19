// A retrying export dispatch of the instance closure (export.slang).
#include "export.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    export_instance(dtid.x + dtid.y * 16776960u, false);
}
