// Retained trait catalog producer (producer.slang): one binding sort key per lane.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sort_init(dispatch_lane(dtid));
}
