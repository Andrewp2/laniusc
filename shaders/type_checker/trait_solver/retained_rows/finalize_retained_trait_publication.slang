// Retained trait publication (retained_route_publication.slang): proof locations, then status.
import type_checker.trait_solver.retained_catalog.retained_route_publication;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    publish_finish();
}
