// One lane per foreign C binding: inserts its identity into the binding
// table. Equal identities name equal bindings (the host checks bindings).

import codegen.x86.link.resident.rl_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint binding = rl_lane(tid);
    if (binding >= gRL.binding_count)
        return;
    uint3 identity = rl_bindings[binding].xyz;
    uint slot = identity_hash(identity) & gRL.hash_mask;
    for (uint probe = 0u; probe <= gRL.hash_mask; probe += 1u)
    {
        uint prior;
        InterlockedCompareExchange(rl_bind_hash[slot], 0u, binding + 1u, prior);
        if (prior == 0u || all(rl_bindings[prior - 1u].xyz == identity))
            return;
        slot = (slot + 1u) & gRL.hash_mask;
    }
    fail(8u);
}
