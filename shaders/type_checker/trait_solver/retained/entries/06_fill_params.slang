// Retained trait catalog producer: the params region's rows (producer.slang).
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = region_lane(RC_R_PARAM, dispatch_lane(dtid));
    if (lane == RC_INVALID) return;
    fill_param(lane, lane_record(lane).y);
}
