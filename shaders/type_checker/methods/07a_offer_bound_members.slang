// Offer required trait members to calls on a lexical type parameter `P`: a
// self member to a dotted call `value.member(...)` whose receiver is `P`
// (directly or behind references), a static one to a path call
// `P::member(...)`. An accepted predicate `P: Trait<A..>` of the call's
// enclosing generic scopes proves the member for every instantiation of `P`,
// so the trait member declaration is the symbolic callee. Concrete replay
// routes it to the selected implementation (methods/09_route_bound_members).
//
// The predicate's arguments bind the trait's parameters: argument i is the
// trait's type parameter i (a trait has no enclosing generic scope, so that is
// its lexical slot i), published as the call's context argument
// (contextual_call_environment.slang) in caller scope. Argument claims and
// result constraints then agree with the bound (calls/03a4), and the member's
// result is the bound's spelling of it. Two predicates that supply one member
// agree only without arguments; otherwise the call is ambiguous.
//
// Predicate rows, owner chains and member contracts are the published
// predicate tables; this pass only joins them. Imported traits still need
// their members offered from the dependency page: offering nothing leaves the
// ordinary unresolved-method rejection in place.
//
// One thread per call expression (HIR domain): the call owns the context
// rows, and its callee member, or the leaf of its callee path, names the
// method token (methods/06 keys an associated call at the leaf).

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
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<uint> compact_type_arg_count;
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
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
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
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<MethodCandidate> method_candidate;
RWStructuredBuffer<uint> call_context_owner_by_token;
RWStructuredBuffer<uint> call_context_arg_mask;
RWStructuredBuffer<uint> call_context_ref_tag;
RWStructuredBuffer<uint> call_context_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint AMBIGUOUS = 0xfffffffeu;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_REFERENCE = 4u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint TRAIT_REFERENCE_DEPENDENCY = 0x80000000u;
static const uint HIR_ITEM = 2u;
static const uint HIR_TYPE = 5u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

#include "../type/instances/lexical_parameter_lookup.slang"

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node < active_hir_count(); }

// The method token of call expression `call`, or INVALID: its callee member's
// name, or the leaf of its qualified callee path `P::member` (a path span ends
// after its leaf). A path callee is also read at its first segment and at the
// callee's value token; `aliases` are those tokens.
uint method_call_token(uint call, out uint2 aliases)
{
    aliases = uint2(INVALID, INVALID);
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_MEMBER_EXPR) return compact_hir_payload[callee].c;
    uint path = compact_hir_core[callee].kind == HIR_NAME_EXPR
        ? compact_hir_links[callee].first_child : callee;
    if (!valid_hir(path) || compact_hir_core[path].kind != HIR_PATH_EXPR) return INVALID;
    HirCore core = compact_hir_core[path];
    if (core.token_end <= core.token_start + 1u) return INVALID;
    aliases = uint2(core.token_start, compact_hir_payload[callee].d);
    return core.token_end - 1u;
}

// The trait HIR item of local trait reference `reference`, or INVALID.
uint local_trait(uint reference)
{
    if ((reference & TRAIT_REFERENCE_DEPENDENCY) != 0u ||
        reference >= min(decl_count_out[0u], gParams.n_tokens)) return INVALID;
    uint trait = decl_hir_node[reference];
    return valid_hir(trait) && compact_hir_core[trait].kind == HIR_ITEM &&
        compact_hir_payload[trait].a == HIR_ITEM_KIND_TRAIT ? trait : INVALID;
}

// The first-declared contract with this name; duplicate required members are
// rejected by trait validation and never select a different member here.
uint trait_member(uint trait, uint name_id)
{
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    if (!valid_hir(trait) || count == 0u) return INVALID;
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
// members of the same name, or one member from two bounds of which one has
// arguments, are ambiguous. `predicate` is the bound that supplied it.
uint bound_member(uint function, uint parameter, uint name_id, out uint predicate)
{
    predicate = INVALID;
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
            uint row = link - 1u;
            if (!valid_hir(row)) return INVALID;
            link = predicate_owner_lookup_next[row];
            if (predicate_owner_node[row] != owner ||
                predicate_status[row] != PREDICATE_STATUS_OK) continue;
            uint subject = lexical_parameter_row(row, predicate_subject_token[row],
                GENERIC_PARAM_KIND_TYPE);
            if (subject == INVALID || generic_param_token[subject] != parameter) continue;
            uint member = trait_member(local_trait(predicate_bound_reference[row]), name_id);
            if (member == INVALID) continue;
            if (found != INVALID && (found != member ||
                predicate_bound_arg_count[row] != 0u ||
                predicate_bound_arg_count[predicate] != 0u)) return AMBIGUOUS;
            found = member;
            predicate = row;
        }
        if (link != 0u) return INVALID;
        uint parent = lexical_parameter_parent(owner);
        if (parent == owner) break;
        owner = parent;
    }
    return found;
}

// Argument `ordinal` of `predicate` as a checked type in caller scope.
uint2 bound_argument(uint predicate, uint ordinal)
{
    HirRange range = compact_type_arg_ranges[predicate];
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    if (range.start > total || ordinal >= range.count || range.start + ordinal >= total)
        return uint2(0u, INVALID);
    uint node = compact_type_args[range.start + ordinal].value;
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_TYPE) return uint2(0u, INVALID);
    uint anchor = compact_hir_core[node].token_start;
    if (anchor >= gParams.n_tokens) return uint2(0u, INVALID);
    uint tag = type_expr_ref_tag[anchor];
    uint payload = type_expr_ref_payload[anchor];
    return tag >= 1u && tag <= 3u && payload != INVALID ? uint2(tag, payload) : uint2(0u, INVALID);
}

// The context slot of the trait's `Self`, or INVALID when its signatures do
// not name `Self`. type/instances/00e gives a trait that uses it a slot after
// its declared type parameters, keyed by the trait's name token.
uint trait_self_slot(uint trait)
{
    if (!valid_hir(trait)) return INVALID;
    uint owner = hir_generic_owner_token(compact_hir_core[trait], compact_hir_payload[trait],
        gParams.n_tokens);
    if (owner >= gParams.n_tokens) return INVALID;
    uint capacity; uint stride;
    type_generic_param_slot_by_token.GetDimensions(capacity, stride);
    return owner < capacity ? type_generic_param_slot_by_token[owner] : INVALID;
}

// Publish the predicate's arguments as call `call`'s context arguments for
// the trait's type parameters, and the bound's subject `subject` (a type
// parameter token) for the trait's `Self`. False when an argument is not a
// checked type or the trait has other parameters.
bool publish_trait_arguments(uint call, uint predicate, uint member_trait, uint subject)
{
    uint count = predicate_bound_arg_count[predicate];
    uint self_slot = trait_self_slot(member_trait);
    if (count == 0u && self_slot == INVALID) return true;
    uint rows; uint stride;
    call_context_ref_tag.GetDimensions(rows, stride);
    if (count > 31u || call >= rows / 32u ||
        compact_generic_param_ranges[member_trait].count != count ||
        (self_slot != INVALID && self_slot != count)) return false;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
        if (bound_argument(predicate, ordinal).x == 0u) return false;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint2 argument = bound_argument(predicate, ordinal);
        call_context_ref_tag[call * 32u + ordinal] = argument.x;
        call_context_ref_payload[call * 32u + ordinal] = argument.y;
    }
    uint slots = count;
    if (self_slot != INVALID)
    {
        call_context_ref_tag[call * 32u + self_slot] = TYPE_REF_GENERIC_PARAM;
        call_context_ref_payload[call * 32u + self_slot] = subject;
        slots += 1u;
    }
    call_context_arg_mask[call] |= slots >= 32u ? 0xffffffffu : (1u << slots) - 1u;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_thread_id_2d(dtid, 65535u, 256u);
    uint2 aliases;
    uint token = method_call_token(call, aliases);
    // A path call `P::member(...)` has no receiver value (methods/06).
    bool dotted = aliases.x == INVALID;
    if (token >= min(token_count[0u], gParams.n_tokens) ||
        method_call_selection_owned[token] == 0u ||
        method_call_name_id[token] == INVALID ||
        (method_call_receiver_hir[token] != INVALID) != dotted) return;
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
    uint predicate;
    uint member = bound_member(encoded - 1u, payload, method_call_name_id[token], predicate);
    if (member == INVALID) return;
    MethodCandidate summary = method_candidate[token];
    MethodCandidate candidate = method_candidate_empty();
    uint mode = member == AMBIGUOUS ? INVALID : method_decl_receiver_mode[member];
    // A path call passes every argument explicitly (methods/07 receiver
    // mode 0), whatever the member's first parameter.
    if (!dotted && (mode == 0u || mode == 3u)) mode = 0u;
    else if (!dotted || (mode != 1u && mode != 2u)) mode = INVALID;
    // A dotted call of a member without a self parameter (or with an
    // explicitly typed one), a path call of a self member, two traits
    // supplying this name, or a bound whose arguments do not bind the
    // trait's parameters cannot be selected.
    uint member_trait = local_trait(predicate_bound_reference[predicate]);
    if (mode != INVALID && publish_trait_arguments(call, predicate, member_trait, payload))
    {
        candidate.state = METHOD_CANDIDATE_UNIQUE;
        candidate.deref_count = depth;
        candidate.module_preference = 0u;
        candidate.callable_kind = METHOD_CALLABLE_LOCAL;
        candidate.local_index = member;
        candidate.matched_ref_tag = tag;
        candidate.matched_ref_payload = payload;
        candidate.receiver_mode = mode;
        if (predicate_bound_arg_count[predicate] != 0u || trait_self_slot(member_trait) != INVALID)
        {
            call_context_owner_by_token[token] = call;
            if (aliases.x < gParams.n_tokens) call_context_owner_by_token[aliases.x] = call;
            if (aliases.y < gParams.n_tokens) call_context_owner_by_token[aliases.y] = call;
        }
    }
    else candidate.state = METHOD_CANDIDATE_INVALID;
    method_candidate_offer(summary, candidate);
    method_candidate[token] = summary;
}
