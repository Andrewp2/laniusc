// Retained trait catalog producer (retained_catalog_producer.slang): binding method rows, impl segment starts, duplicates.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    sort_finish(dispatch_lane(dtid));
}
