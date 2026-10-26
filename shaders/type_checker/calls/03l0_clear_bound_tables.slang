// Empty the bound-directed inference tables before a round rebuilds them
// (bound_tables.slang).
import type_checker.calls.bound_tables;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x < 4u && dtid.y == 0u) bound_inference_counts[dtid.x] = 0u;
}
