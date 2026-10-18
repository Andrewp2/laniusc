// One instance-closure round: one lane per frontier instance (F, E). Each
// edge of F (a call to a generic local body inside F) gets its call
// environment substituted under E, and the callee's instance is inserted
// one level deeper. Edges whose environment stays open or has a hole under
// E are counted and left to the replays.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.closure.instance_closure;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

static const uint INVALID = 0xffffffffu;

#include "closure_calls.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = instance_closure_counts[IC_COUNT_START] + dtid.x + dtid.y * 16776960u;
    if (index >= instance_closure_counts[IC_COUNT_END]) return;
    uint4 instance = instance_closure_instances[2u * index];
    if (!valid_node(instance.y)) return;
    CtSpare subst_spare = ct_spare_none();
    CtSpare env_spare = ct_spare_none();
    uint link = ic_first_edge(instance.y);
    for (uint step = 0u; step < hir_count() && link != 0u; step++)
    {
        uint call = link - 1u;
        link = ic_next_edge(call);
        uint token; uint callee; uint2 masks;
        if (!valid_node(call) || !closure_call(call, token, callee, masks)) continue;
        uint key = closure_instance_env(token, callee, masks, instance.x, subst_spare, env_spare);
        if (!ct_is_record(key))
        {
            ic_count(IC_COUNT_SKIPPED);
            continue;
        }
        ic_insert(key, callee, instance.z + 1u, call);
    }
}
