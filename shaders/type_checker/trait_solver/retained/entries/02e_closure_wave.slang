// Retained trait catalog producer (producer.slang): every closure wave in one workgroup.
import type_checker.trait_solver.retained.producer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 local: SV_GroupThreadID)
{
    closure_waves(local.x);
}
