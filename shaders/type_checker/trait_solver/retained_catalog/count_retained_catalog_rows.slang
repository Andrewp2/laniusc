// Retained trait catalog producer (retained_catalog_producer.slang): count_lane over every lane.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dispatch_lane(dtid);
    if (lane < lanes()) count_lane(lane);
}
