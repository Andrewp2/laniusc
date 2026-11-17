// Retained trait catalog producer (producer.slang): mark_lane over every lane;
// lane 0 also checks the configured store counters.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dispatch_lane(dtid);
    if (lane == 0u) check_counts();
    if (lane < lanes()) mark_lane(lane);
}
