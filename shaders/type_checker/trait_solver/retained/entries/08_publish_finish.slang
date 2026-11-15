// Retained trait publication (publish.slang): proof locations, then status.
import type_checker.trait_solver.retained.publish;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    publish_finish();
}
