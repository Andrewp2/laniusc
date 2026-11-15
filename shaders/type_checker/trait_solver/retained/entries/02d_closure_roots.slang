// Retained trait catalog producer (producer.slang): closure roots from the directory, trait and use lanes.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    closure_roots(dispatch_lane(dtid));
}
