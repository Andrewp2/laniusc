// Retained trait catalog producer (retained_catalog_producer.slang): the bitonic steps with
// j < 256 of one 512-key block, in shared memory.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group: SV_GroupID, uint3 thread: SV_GroupThreadID)
{
    sort_block(group.x + group.y * 65535u, thread.x);
}
