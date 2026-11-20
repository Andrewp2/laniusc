// The last workgroup advances the source and final field closure runs.
import type_checker.substitution.field_closure;
import type_checker.substitution.field_closure_steps;
import type_checker.substitution.field_closure_progress;

RWStructuredBuffer<uint> ct_expand_args_next;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint index = ct_expand_counts[CT_EXPAND_START] + lane / CT_EXPAND_LANES_PER_ENTRY;
    if (lane % CT_EXPAND_LANES_PER_ENTRY == 0u && index < ct_expand_counts[CT_EXPAND_END]) expand_field_closure_entry(index);
    uint3 launched = ct_expand_level_args(ct_expand_level_groups());
    // Every lane's queue writes are visible device-wide before lane 0
    // counts the workgroup finished.
    AllMemoryBarrierWithGroupSync();
    if (ltid.x != 0u) return;
    uint done;
    InterlockedAdd(ct_expand_counts[CT_EXPAND_DONE], 1u, done);
    if (done + 1u != launched.x * launched.y) return;
    DeviceMemoryBarrier();
    ct_expand_counts[CT_EXPAND_DONE] = 0u;
    uint3 args = advance_field_closure();
    ct_expand_args_next[0u] = args.x;
    ct_expand_args_next[1u] = args.y;
    ct_expand_args_next[2u] = args.z;
}
