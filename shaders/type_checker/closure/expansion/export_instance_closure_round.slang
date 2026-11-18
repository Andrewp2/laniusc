// A retrying export dispatch of the instance closure (type_checker/closure/instance_closure_export.slang).
#include "../instance_closure_export.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    export_instance(dtid.x + dtid.y * 16776960u, false);
}
