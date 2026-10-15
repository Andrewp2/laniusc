// Offer required trait members to receivers whose type is a lexical type
// parameter `P`: a self member to a dotted call `value.member(...)`, a static
// one to a path call `P::member(...)`. An accepted predicate `P: Trait` of the call's enclosing
// generic scopes proves the member for every instantiation of `P`, so the
// trait member declaration is the symbolic callee. Concrete replay routes it
// to the selected implementation (methods/09_route_bound_members).
//
// Predicate rows, owner chains and member contracts are the published
// predicate tables; this pass only joins them. Imported traits and traits
// with arguments still need member-signature substitution: offering nothing
// leaves the ordinary unresolved-method rejection in place.

import gpu_index;
import hir_records;
import type_checker.methods.candidate;
import type_checker.predicates.owner_lookup;
import type_checker.predicates.method_contract_lookup;
import type_checker.type.instances.generic_param_lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<uint> method_call_selection_owned;
StructuredBuffer<uint> method_call_receiver_hir;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_source_ref_tag;
StructuredBuffer<uint> method_call_source_ref_payload;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> predicate_owner_lookup_head;
StructuredBuffer<uint> predicate_owner_lookup_next;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> predicate_bound_arg_count;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_method_contract_lookup_head;
StructuredBuffer<uint> predicate_method_contract_lookup_next;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_method_contract_name_token;
StructuredBuffer<uint> predicate_method_contract_status;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_lookup_state;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_token;
RWStructuredBuffer<MethodCandidate> method_candidate;

static const uint INVALID = 0xffffffffu;
static const uint AMBIGUOUS = 0xfffffffeu;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_REFERENCE = 4u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint TRAIT_REFERENCE_DEPENDENCY = 0x80000000u;
static const uint HIR_ITEM = 2u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;

#include "../type/instances/lexical_parameter_lookup.slang"

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node < active_hir_count(); }

// The first-declared contract with this name; duplicate required members are
// rejected by trait validation and never select a different member here.
uint trait_member(uint reference, uint name_id)
{
    if ((reference & TRAIT_REFERENCE_DEPENDENCY) != 0u ||
        reference >= min(decl_count_out[0u], gParams.n_tokens)) return INVALID;
    uint trait = decl_hir_node[reference];
    if (!valid_hir(trait) || compact_hir_core[trait].kind != HIR_ITEM ||
        compact_hir_payload[trait].a != HIR_ITEM_KIND_TRAIT) return INVALID;
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    if (count == 0u) return INVALID;
    uint link = predicate_method_contract_lookup_head[
        method_contract_lookup_bucket(trait, name_id, count)];
    uint best = INVALID;
    for (uint visited = 0u; link != 0u && visited < count; visited++)
    {
        uint method = link - 1u;
        if (!valid_hir(method)) return INVALID;
        link = predicate_method_contract_lookup_next[method];
        uint token = predicate_method_contract_name_token[method];
        if (predicate_method_contract_owner_hir[method] == trait &&
            predicate_method_contract_name_id[method] == name_id &&
            predicate_method_contract_status[method] == PREDICATE_STATUS_OK &&
            token < gParams.n_tokens && token < best)
            best = token;
    }
    return link == 0u ? best : INVALID;
}

// Walk the call's generic scopes outward, as caller contract proofs do. Every
// accepted bound on exactly this parameter may contribute; two different
// members of the same name are ambiguous.
uint bound_member(uint function, uint parameter, uint name_id)
{
    uint count = min(compact_predicate_count[0u], gParams.n_hir_nodes);
    if (count == 0u) return INVALID;
    uint found = INVALID;
    uint owner = function;
    for (uint depth = 0u; depth < active_hir_count() && valid_hir(owner); depth++)
    {
        uint owner_token = hir_generic_owner_token(compact_hir_core[owner],
            compact_hir_payload[owner], gParams.n_tokens);
        if (owner_token >= gParams.n_tokens) return INVALID;
        uint link = predicate_owner_lookup_head[predicate_owner_lookup_bucket(owner_token, count)];
        for (uint visited = 0u; visited < count && link != 0u; visited++)
        {
            uint predicate = link - 1u;
            if (!valid_hir(predicate)) return INVALID;
            link = predicate_owner_lookup_next[predicate];
            if (predicate_owner_node[predicate] != owner ||
                predicate_status[predicate] != PREDICATE_STATUS_OK ||
                predicate_bound_arg_count[predicate] != 0u) continue;
            uint row = lexical_parameter_row(predicate, predicate_subject_token[predicate],
                GENERIC_PARAM_KIND_TYPE);
            if (row == INVALID || generic_param_token[row] != parameter) continue;
            uint member = trait_member(predicate_bound_reference[predicate], name_id);
            if (member == INVALID) continue;
            if (found != INVALID && found != member) return AMBIGUOUS;
            found = member;
        }
        if (link != 0u) return INVALID;
        uint parent = lexical_parameter_parent(owner);
        if (parent == owner) break;
        owner = parent;
    }
    return found;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id_2d(dtid, 65535u, 256u);
    if (token >= min(token_count[0u], gParams.n_tokens) ||
        method_call_selection_owned[token] == 0u ||
        method_call_name_id[token] == INVALID) return;
    // A path call `P::member(...)` has no receiver value (methods/06).
    bool dotted = method_call_receiver_hir[token] != INVALID;
    uint tag = method_call_source_ref_tag[token];
    uint payload = method_call_source_ref_payload[token];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    // Auto-reference receivers reach the parameter through reference layers,
    // at the same dereference rank as table lookup would assign.
    uint depth = 0u;
    for (; depth < 64u && tag == TYPE_REF_INSTANCE && payload < capacity &&
         type_instance_kind[payload] == TYPE_INSTANCE_REFERENCE; depth++)
    {
        uint source = payload;
        tag = type_instance_elem_ref_tag[source];
        payload = type_instance_elem_ref_payload[source];
    }
    if (tag != TYPE_REF_GENERIC_PARAM || payload >= gParams.n_tokens) return;
    uint encoded = enclosing_fn[token];
    if (encoded == 0u || !valid_hir(encoded - 1u)) return;
    uint member = bound_member(encoded - 1u, payload, method_call_name_id[token]);
    if (member == INVALID) return;
    MethodCandidate summary = method_candidate[token];
    MethodCandidate candidate = method_candidate_empty();
    uint mode = member == AMBIGUOUS ? INVALID : method_decl_receiver_mode[member];
    // A path call passes every argument explicitly (methods/07 receiver
    // mode 0), whatever the member's first parameter.
    if (!dotted && (mode == 0u || mode == 3u)) mode = 0u;
    else if (!dotted || (mode != 1u && mode != 2u)) mode = INVALID;
    if (mode == INVALID)
    {
        // A dotted call of a member without a self parameter (or with an
        // explicitly typed one), a path call of a self member, or two traits
        // supplying this name cannot be selected.
        candidate.state = METHOD_CANDIDATE_INVALID;
    }
    else
    {
        candidate.state = METHOD_CANDIDATE_UNIQUE;
        candidate.deref_count = depth;
        candidate.module_preference = 0u;
        candidate.callable_kind = METHOD_CALLABLE_LOCAL;
        candidate.local_index = member;
        candidate.matched_ref_tag = tag;
        candidate.matched_ref_payload = payload;
        candidate.receiver_mode = mode;
    }
    method_candidate_offer(summary, candidate);
    method_candidate[token] = summary;
}
