// Retained trait catalog producer (producer.slang): one bitonic compare-exchange per lane.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sort_step(dispatch_lane(dtid));
}
