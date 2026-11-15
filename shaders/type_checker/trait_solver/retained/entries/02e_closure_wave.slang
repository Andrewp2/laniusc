// Retained trait catalog producer (producer.slang): the next frontier wave and its indirect dispatch.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    closure_wave();
}
