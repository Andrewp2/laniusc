// Late member lookup may resolve more values. Their metadata is projected
// without replacing already-normalized type annotations with interface rows.
#define PROJECT_DEPENDENCY_VALUES_ONLY 1
#include "11_project_types.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    project_dependency_types(dtid);
}
