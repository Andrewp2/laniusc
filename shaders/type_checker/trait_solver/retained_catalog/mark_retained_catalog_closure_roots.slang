// Retained trait catalog producer (retained_catalog_producer.slang): closure roots from the directory, trait and use lanes.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    closure_roots(dispatch_lane(dtid));
}
