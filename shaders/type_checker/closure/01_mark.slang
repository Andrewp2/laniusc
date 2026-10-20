// Edges and roots of the instance closure (instance_closure.slang). One lane
// per call node whose callee is a generic local body. A call inside a
// function with a generic environment is an edge of that function; a call
// inside a nongeneric function whose environment is complete and closed is
// a root instance at depth 1. A bound-member call (closure_bound_call) is
// an edge of its generic function too; 03c routes it.
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
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> compact_hir_nearest_fn;

static const uint INVALID = 0xffffffffu;

#include "closure_calls.slang"

// Parameters of any lexical ancestor make the body generic (as
// 04_owner_spans and codegen's function_has_generic_environment).
bool has_generic_environment(uint row)
{
    uint owner = row;
    for (uint depth = 0u; depth < hir_count(); depth++)
    {
        if (compact_generic_param_ranges[owner].count != 0u) return true;
        uint parent = compact_hir_core[owner].parent;
        if (parent == INVALID || parent >= owner) return false;
        owner = parent;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (call >= hir_count()) return;
    uint token; uint callee; uint2 masks;
    if (!closure_call(call, token, callee, masks))
    {
        // A bound-member call is an edge of its generic function (03c).
        uint bound_owner = compact_hir_nearest_fn[call];
        if (closure_bound_call(call, token) && valid_node(bound_owner) &&
            compact_hir_core[bound_owner].kind == HIR_FN && has_generic_environment(bound_owner))
            ic_link_edge(bound_owner, call);
        return;
    }
    uint owner = compact_hir_nearest_fn[call];
    if (!valid_node(owner) || compact_hir_core[owner].kind != HIR_FN) return;
    if (has_generic_environment(owner))
    {
        ic_link_edge(owner, call);
        return;
    }
    CtSpare subst_spare = ct_spare_none();
    CtSpare env_spare = ct_spare_none();
    uint key = closure_instance_env(token, callee, masks, CT_NONE, subst_spare, env_spare);
    if (ct_is_record(key)) ic_insert(key, callee, 1u, call);
}
