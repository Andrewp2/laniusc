// Retained trait publication (publish.slang): one route per obligation, one
// call status per use.
import type_checker.trait_solver.retained.publish;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    publish_route(publish_lane(dtid));
}
