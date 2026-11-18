// Retained trait catalog producer (retained_catalog_producer.slang): one binding sort key per lane.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sort_init(dispatch_lane(dtid));
}
