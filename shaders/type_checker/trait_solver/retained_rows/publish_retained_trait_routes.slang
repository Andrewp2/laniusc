// Retained trait publication (retained_route_publication.slang): one route per obligation, one
// call status per use.
import type_checker.trait_solver.retained_catalog.retained_route_publication;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    publish_route(publish_lane(dtid));
}
