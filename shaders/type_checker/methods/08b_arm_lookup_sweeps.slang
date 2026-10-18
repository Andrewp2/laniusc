// Arm the preliminary method-lookup sweeps.
//
// The sweeps dispatch from method_lookup_dispatch_args, a copy of the ordinary
// method grids, rather than from the grids themselves. 08c_gate_lookup_sweep
// zeroes the copy after a sweep that publishes no target change, so the
// remaining sweeps launch no workgroups.
//
// method_lookup_dispatch_args holds four three-word grids (method tokens,
// method HIR, method tokens or HIR, active HIR) and, at word 12, the target
// change count (call_inference_state[1]) after the last sweep that changed a
// target. Finalization is the only sweep pass that bumps that count.

StructuredBuffer<uint> method_token_dispatch_args;
StructuredBuffer<uint> method_hir_dispatch_args;
StructuredBuffer<uint> method_token_hir_dispatch_args;
StructuredBuffer<uint> hir_active_dispatch_args;
StructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> method_lookup_dispatch_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    method_lookup_dispatch_args[0u] = method_token_dispatch_args[0u];
    method_lookup_dispatch_args[1u] = method_token_dispatch_args[1u];
    method_lookup_dispatch_args[2u] = method_token_dispatch_args[2u];
    method_lookup_dispatch_args[3u] = method_hir_dispatch_args[0u];
    method_lookup_dispatch_args[4u] = method_hir_dispatch_args[1u];
    method_lookup_dispatch_args[5u] = method_hir_dispatch_args[2u];
    method_lookup_dispatch_args[6u] = method_token_hir_dispatch_args[0u];
    method_lookup_dispatch_args[7u] = method_token_hir_dispatch_args[1u];
    method_lookup_dispatch_args[8u] = method_token_hir_dispatch_args[2u];
    method_lookup_dispatch_args[9u] = hir_active_dispatch_args[0u];
    method_lookup_dispatch_args[10u] = hir_active_dispatch_args[1u];
    method_lookup_dispatch_args[11u] = hir_active_dispatch_args[2u];
    method_lookup_dispatch_args[12u] = call_inference_state[1u];
}
