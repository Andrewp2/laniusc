// Retained trait catalog producer: the uses region's rows (retained_catalog_producer.slang).
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = region_lane(RC_R_USE, dispatch_lane(dtid));
    if (lane == RC_INVALID) return;
    fill_use(lane, lane_record(lane).y);
}
