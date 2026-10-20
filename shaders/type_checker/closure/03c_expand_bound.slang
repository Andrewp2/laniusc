// One instance-closure round over bound-member edges (D3; 01_mark links
// them): one lane per frontier instance (F, E). Each bound-member call of F,
// `value.member(...)` with `value` of F's type parameter P, routes under E
// as methods/09 routes it in a replay: the closed receiver R = E(P) selects
// the implementation of the member's trait whose receiver pattern matches R.
// A nongeneric implementation's method is concrete and needs no instance. A
// generic one's method is inserted one level deeper with the environment
// its pattern binds from R and its routed target (instance_closure_targets).
//
// v1 routes a pattern that is R's named head applied to the implementation's
// type parameters (each slot at least once) or to closed arguments equal to
// R's. Anything else leaves the edge to the replays: a nested or constant
// parameter, a method with parameters of its own, an imported trait or
// receiver head, a pattern without a canonical ID, or no unique match.
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
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_lookup_head;
StructuredBuffer<uint> method_lookup_next;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> fn_start_token_by_decl_token;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;

static const uint INVALID = 0xffffffffu;
static const uint BOUND_NO_MATCH = 0u;
static const uint BOUND_CONCRETE = 1u;
static const uint BOUND_GENERIC = 2u;
static const uint BOUND_UNKNOWN = 3u;
static const uint TRAIT_REFERENCE_DEPENDENCY_BIT = 0x80000000u;

#include "closure_calls.slang"

// Whether implementation `impl` implements local trait item `trait`
// (methods/09 `implements`, local bound).
bool implements_local(uint impl, uint trait)
{
    if (!valid_node(impl)) return false;
    uint reference = predicate_bound_reference[impl];
    return (reference & TRAIT_REFERENCE_DEPENDENCY_BIT) == 0u &&
        reference < min(decl_count_out[0u], gParams.n_tokens) && decl_hir_node[reference] == trait;
}

// The type slot of pattern leaf `leaf`, or INVALID for a constant or
// dependency parameter or a slot at or past `count`.
uint pattern_slot(uint leaf, uint count)
{
    if (!ct_is_type_param(leaf) || ct_is_dep_param(leaf)) return INVALID;
    uint slot = SourceSlots().type_slot(ct_param_token(leaf));
    return slot < count ? slot : INVALID;
}

// The receiver's argument where pattern `pattern` first spells type slot
// `slot` (helper: the loop returns from inside instead of breaking).
uint slot_binding(uint pattern, uint actual, uint slot, uint count)
{
    uint arity = ct_arity(pattern);
    for (uint index = 0u; index < arity; index++)
        if (pattern_slot(ct_arg(pattern, index), count) == slot) return ct_arg(actual, index);
    return CT_UNKNOWN;
}

// The type slots generic pattern `pattern` binds against receiver `actual`
// (see the file comment), or INVALID when they do not match that way.
// `flat` is false when the pattern has a child this v1 cannot compare.
uint bind_flat_pattern(uint pattern, uint actual, uint count, out bool flat)
{
    flat = true;
    if (!ct_is_stored(pattern) || !ct_is_stored(actual) || any(ct_head[pattern] != ct_head[actual]))
        return INVALID;
    uint arity = ct_arity(pattern);
    uint bound = 0u;
    for (uint index = 0u; index < arity; index++)
    {
        uint child = ct_arg(pattern, index);
        uint value = ct_arg(actual, index);
        if (ct_is_param(child))
        {
            uint slot = pattern_slot(child, count);
            if (slot == INVALID) { flat = false; return INVALID; }
            if (!ct_closed(value) || ct_is_constant(value)) return INVALID;
            uint bit = 1u << slot;
            if ((bound & bit) != 0u && slot_binding(pattern, actual, slot, count) != value) return INVALID;
            bound |= bit;
        }
        else if (!ct_closed(child)) { flat = false; return INVALID; }
        else if (child != value || !ct_is_resolved(child)) return INVALID;
    }
    return bound;
}

// How method row `row` answers bound call `name_id` of trait `trait` on
// receiver `actual` (BOUND_*); `parameters` is its implementation's type
// parameter count.
uint match_candidate(uint row, uint name_id, uint trait, uint actual, out uint parameters)
{
    parameters = 0u;
    HirMethodCore core = compact_method_cores[row];
    uint candidate = core.name_token;
    if (!valid_token(candidate) || method_decl_name_id[candidate] != name_id ||
        !implements_local(core.impl_node, trait)) return BOUND_NO_MATCH;
    uint pattern = ct_ref(method_decl_receiver_ref_tag[candidate], method_decl_receiver_ref_payload[candidate]);
    if (!ct_is_resolved(pattern)) return BOUND_UNKNOWN;
    parameters = compact_generic_param_ranges[core.impl_node].count;
    if (parameters == 0u) return ct_closed(pattern) && pattern == actual ? BOUND_CONCRETE : BOUND_NO_MATCH;
    uint member = fn_hir_by_decl_token[candidate];
    uint impl_token = hir_generic_owner_token(compact_hir_core[core.impl_node],
        compact_hir_payload[core.impl_node], gParams.n_tokens);
    if (parameters >= 32u || !valid_node(member) || compact_generic_param_ranges[member].count != 0u ||
        !valid_token(impl_token) || type_decl_const_param_count_by_owner_token[impl_token] != 0u)
        return BOUND_UNKNOWN;
    bool flat;
    uint bound = bind_flat_pattern(pattern, actual, parameters, flat);
    if (!flat) return BOUND_UNKNOWN;
    if (bound == INVALID) return BOUND_NO_MATCH;
    return countbits(bound) == parameters ? BOUND_GENERIC : BOUND_UNKNOWN;
}

// Route bound call `call` (method token `token`) of frontier instance
// `instance` and insert the generic implementation method it reaches.
void route_bound_edge(uint call, uint token, uint4 instance, inout CtSpare subst_spare,
    inout CtSpare env_spare)
{
    uint receiver = ct_subst(SourceSlots(), instance.x,
        ct_ref(TYPE_REF_GENERIC_PARAM, method_call_receiver_ref_payload[token]), true, subst_spare);
    uint declaration = ct_named_decl_token(receiver);
    uint name_id = method_call_name_id[token];
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    if (!ct_is_resolved(receiver) || !ct_closed(receiver) || !valid_token(declaration) ||
        name_id == INVALID || count == 0u)
    {
        ic_count(IC_COUNT_SKIPPED);
        return;
    }
    uint trait = bound_member_trait(call_fn_index[token]);
    MethodReceiverHead head;
    head.shape = 3u;
    head.identity = uint3(declaration, 0u, 0u);
    head.arity = ct_arity(receiver);
    uint link = method_lookup_head[method_lookup_bucket(head, name_id, count)];
    uint matches = 0u;
    uint selected = INVALID;
    uint selected_parameters = 0u;
    bool unknown = false;
    for (uint visited = 0u; visited < count && link != 0u; visited++)
    {
        uint row = link - 1u;
        if (row >= count) { unknown = true; link = 0u; continue; }
        link = method_lookup_next[row];
        uint parameters;
        uint answer = match_candidate(row, name_id, trait, receiver, parameters);
        if (answer == BOUND_UNKNOWN) unknown = true;
        if (answer != BOUND_CONCRETE && answer != BOUND_GENERIC) continue;
        matches++;
        selected = answer == BOUND_GENERIC ? row : INVALID;
        selected_parameters = parameters;
    }
    if (unknown || matches != 1u)
    {
        ic_count(IC_COUNT_SKIPPED);
        return;
    }
    // A nongeneric implementation's method is concrete.
    if (selected == INVALID) return;
    HirMethodCore core = compact_method_cores[selected];
    uint candidate = core.name_token;
    uint member = fn_hir_by_decl_token[candidate];
    uint pattern = ct_ref(method_decl_receiver_ref_tag[candidate], method_decl_receiver_ref_payload[candidate]);
    uint parameters = selected_parameters;
    CtKey key = ct_key_begin(CT_KIND_ENV, parameters, parameters,
        uint3(member + 1u, low_bits(parameters), 0u));
    if (!ct_spare_reserve(env_spare, key)) return;
    for (uint slot = 0u; slot < parameters; slot++)
        ct_key_arg(key, slot, slot_binding(pattern, receiver, slot, parameters));
    if (!key.ok || (key.flags & (CTF_TYPE_PARAM | CTF_CONST_PARAM)) != 0u) return;
    uint env = ct_spare_publish(key, uint2(0xffffffffu, 0u), true, env_spare);
    if (!ct_is_record(env)) return;
    // The routed callee as methods/09 publishes it and host retention reads
    // it: its function start token (backend_call_fn_index), and a public
    // method's HIR or a private one's start token as its native symbol.
    uint start = fn_start_token_by_decl_token[candidate];
    start = valid_token(start) ? start : candidate;
    bool public_method = (compact_method_signatures[selected].metadata & 0xffffu) == 1u;
    uint4 target = uint4(start, public_method ? (0x80000000u | core.node) : (0x40000000u | start),
        0x80000000u | core.node, parameters);
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
