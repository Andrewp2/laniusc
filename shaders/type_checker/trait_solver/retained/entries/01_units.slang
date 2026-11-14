// Retained trait catalog producer (producer.slang): unit_lane over every lane.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dispatch_lane(dtid);
    if (lane < lanes()) unit_lane(lane);
}
