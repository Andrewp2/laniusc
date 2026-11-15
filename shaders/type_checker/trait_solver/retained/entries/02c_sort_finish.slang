// Retained trait catalog producer (producer.slang): binding method rows, impl segment starts, duplicates.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sort_finish(dispatch_lane(dtid));
}
