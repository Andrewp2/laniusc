// Stop the preliminary method-lookup sweeps once one changes nothing.
//
// Runs after each sweep (see 08b_arm_lookup_sweeps for the layout). A sweep
// re-derives every receiver key and candidate from published targets, call
// results and declaration facts, and only finalization publishes targets,
// bumping call_inference_state[1] whenever one changes. A sweep without a bump
// therefore leaves the next sweep the same inputs: every later sweep would
// repeat it. Zeroing the grids skips them without a host readback.

StructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> method_lookup_dispatch_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint changes = call_inference_state[1u];
    if (changes != method_lookup_dispatch_args[12u])
    {
        method_lookup_dispatch_args[12u] = changes;
        return;
    }
    method_lookup_dispatch_args[0u] = 0u;
    method_lookup_dispatch_args[1u] = 0u;
    method_lookup_dispatch_args[2u] = 0u;
    method_lookup_dispatch_args[3u] = 0u;
    method_lookup_dispatch_args[4u] = 0u;
    method_lookup_dispatch_args[5u] = 0u;
    method_lookup_dispatch_args[6u] = 0u;
    method_lookup_dispatch_args[7u] = 0u;
    method_lookup_dispatch_args[8u] = 0u;
    method_lookup_dispatch_args[9u] = 0u;
    method_lookup_dispatch_args[10u] = 0u;
    method_lookup_dispatch_args[11u] = 0u;
}
