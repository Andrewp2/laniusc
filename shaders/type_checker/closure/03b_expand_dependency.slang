// One dependency closure round (D1b; summary.slang): one lane per frontier
// instance whose callee is a summary function (SUMMARY_TAG). Each edge of
// that function has its slot-form bindings substituted under the
// instance's tagged environment (a dependency slot leaf binds its slot), and
// the callee's instance is inserted one level deeper with the job-wide
// edge index as its template (the host maps it back to the library's
// retained call). 03_expand skips these instances (their callee is not a
// HIR row); an edge whose environment stays open, has a hole, or names a
// node the import left unresolved is counted and left to the replays.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.closure.instance_closure;
import type_checker.closure.summary;

static const uint INVALID = 0xffffffffu;

// The tagged environment of edge `e` (callee function `callee`, masks
// `masks`, bindings at `first`) under instance environment `caller`:
// CT_NONE when a binding stays open, CT_UNKNOWN when one is unresolved.
uint edge_instance_env(uint callee, uint2 masks, uint first, uint caller,
    inout CtSpare subst_spare, inout CtSpare env_spare)
{
    uint types = countbits(masks.x);
    uint arity = types + countbits(masks.y);
    CtKey key = ct_key_begin(CT_KIND_ENV, arity, types, uint3(SUMMARY_TAG | callee, masks.x, masks.y));
    if (!ct_spare_reserve(env_spare, key)) return CT_UNKNOWN;
    for (uint index = 0u; index < arity; index++)
    {
        uint pattern = summary_node_ref(summary_arg(first + index));
        if (!ct_is_resolved(pattern)) return CT_UNKNOWN;
        uint binding = ct_subst(SourceSlots(), caller, pattern, true, subst_spare);
        if (!ct_is_resolved(binding)) return CT_UNKNOWN;
        ct_key_arg(key, index, binding);
    }
    if (!key.ok) return CT_UNKNOWN;
    if ((key.flags & (CTF_TYPE_PARAM | CTF_CONST_PARAM)) != 0u) return CT_NONE;
    return ct_spare_publish(key, uint2(0xffffffffu, 0u), true, env_spare);
}

// The edge row after `e` (helper, so the walk carries one loaded value).
uint4 next_edge(uint e) { return summary_edge(e + 1u); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = instance_closure_counts[IC_COUNT_START] + dtid.x + dtid.y * 16776960u;
    if (index >= instance_closure_counts[IC_COUNT_END]) return;
    uint4 instance = instance_closure_instances[2u * index];
    if ((instance.y & SUMMARY_TAG) == 0u) return;
    uint2 edges = summary_fn_edges(instance.y & ~SUMMARY_TAG);
    CtSpare subst_spare = ct_spare_none();
    CtSpare env_spare = ct_spare_none();
    uint4 edge = summary_edge(edges.x);
    for (uint e = edges.x; e < edges.y; e++)
    {
        uint4 current = edge;
        edge = next_edge(e);
        if (current.x >= summary_fn_count()) continue;
        uint key = edge_instance_env(current.x, current.yz, current.w, instance.x, subst_spare, env_spare);
        if (!ct_is_record(key))
        {
            ic_count(IC_COUNT_SKIPPED);
            continue;
        }
        ic_insert(key, SUMMARY_TAG | current.x, instance.z + 1u, e);
    }
}
