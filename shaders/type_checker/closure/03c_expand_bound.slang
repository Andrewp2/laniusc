// One instance-closure round over bound-member edges (D3; 01_mark links
// them): one lane per frontier instance (F, E). Each bound-member call of F,
// `value.member(...)` with `value` of F's type parameter P, routes under E
// as methods/09 routes it in a replay (bound_route.slang). A nongeneric
// implementation's method is concrete and needs no instance. A generic one's
// method is inserted one level deeper with the environment its pattern binds
// from R and its routed target (instance_closure_targets).
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.closure.instance_closure;
import type_checker.methods.lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> fn_start_token_by_decl_token;

static const uint INVALID = 0xffffffffu;

#include "closure_calls.slang"
#include "bound_route.slang"

// Route bound call `call` (method token `token`) of frontier instance
// `instance` and insert the generic implementation method it reaches.
void route_bound_edge(uint call, uint token, uint4 instance, inout CtSpare subst_spare,
    inout CtSpare env_spare)
{
    uint env;
    uint selected = route_bound_call(token, instance.x, subst_spare, env_spare, env);
    if (selected == INVALID)
    {
        ic_count(IC_COUNT_SKIPPED);
        return;
    }
    // A nongeneric implementation's method is concrete.
    if (!ct_is_record(env)) return;
    HirMethodCore core = compact_method_cores[selected];
    uint candidate = core.name_token;
    uint member = fn_hir_by_decl_token[candidate];
    // The routed callee as methods/09 publishes it and host retention reads
    // it: its function start token (backend_call_fn_index), and a public
    // method's HIR or a private one's start token as its native symbol;
    // then its type parameter count, and its constant parameter count
    // shifted by 16.
    uint start = fn_start_token_by_decl_token[candidate];
    start = valid_token(start) ? start : candidate;
    bool public_method = (compact_method_signatures[selected].metadata & 0xffffu) == 1u;
    uint types = ct_type_slots(env);
    uint4 target = uint4(start, public_method ? (0x80000000u | core.node) : (0x40000000u | start),
        0x80000000u | core.node, types | ((ct_arity(env) - types) << 16u));
    ic_insert_target(env, member, instance.z + 1u, call, target);
}

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
        uint token;
        if (valid_node(call) && closure_bound_call(call, token))
            route_bound_edge(call, token, instance, subst_spare, env_spare);
    }
}
