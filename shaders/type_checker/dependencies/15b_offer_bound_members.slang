// Offer the required members of imported traits to calls on a lexical type
// parameter `P`, on each dependency page: a self member to a dotted call
// `value.member(...)` whose receiver is `P` (directly or behind references),
// a static one to a path call `P::member(...)`. methods/07a offers the
// members of local traits the same way.
//
// An accepted predicate `P: path::Trait<A..>` of the call's enclosing generic
// scopes proves the member for every instantiation of `P`, so the trait's
// required member is the symbolic callee. Its identity is portable: the
// trait's library and unit, and the member's interface symbol. The second
// page visit (15_project_methods, 07b) publishes its signature from the page
// that holds the trait; body specialization routes the call to the selected
// implementation (methods/09_route_bound_members).
//
// The predicate's arguments bind the trait's parameters: argument i is the
// trait's type parameter i, published as the call's context argument
// (contextual_call_environment.slang) in caller scope, as 07a does. A trait
// on another page contributes nothing here; that page's visit offers it, and
// candidates from several bounds meet in method_candidate_offer.
//
// One thread per call expression (HIR domain): the call owns the context
// rows, and its callee member, or the leaf of its callee path, names the
// method token (methods/06 keys an associated call at the leaf).

import gpu_index;
import hir_records;
import dependency_interface;
import semantic_interface_layout;
import type_checker.methods.candidate;
import type_checker.predicates.owner_lookup;
import type_checker.predicates.trait_reference;
import type_checker.type.instances.generic_param_lookup;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};
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
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<uint> method_call_selection_owned;
StructuredBuffer<uint> method_call_receiver_hir;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_source_ref_tag;
StructuredBuffer<uint> method_call_source_ref_payload;
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
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_lookup_state;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_token;
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
static const uint MEMBER_TRAIT_METHOD = 7u;
static const uint DECLARATION_TRAIT = 10u;
static const uint HIR_TYPE = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint DISPATCH_X_STRIDE = 16776960u;

// Token-indexed rows; the visibility capacity may exceed the token capacity.
uint token_capacity()
{
    uint rows; uint stride;
    method_call_selection_owned.GetDimensions(rows, stride);
    return rows;
}

#define LEXICAL_HIR_CAPACITY gParams.hir_capacity
#define LEXICAL_TOKEN_CAPACITY token_capacity()
#include "../type/instances/lexical_parameter_lookup.slang"

uint active_hir_count() { return min(compact_hir_count[0u], gParams.hir_capacity); }
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

// The trait declaration row on this page of dependency trait reference
// `reference`, or INVALID (a local trait, or a trait on another page).
uint page_trait(uint reference)
{
    if (!trait_reference_is_dependency(reference)) return INVALID;
    uint paths; uint stride;
    resolved_dependency_library_id.GetDimensions(paths, stride);
    if (trait_reference_path(reference) >= paths) return INVALID;
    uint4 identity = trait_reference_identity(reference);
    uint declaration = dependency_find_declaration(identity.y, identity.z, identity.w);
    return declaration < dependency_declaration_count() &&
        dependency_declaration_word(declaration * 14u + 6u) == DECLARATION_TRAIT
        ? declaration : INVALID;
}

// The first-declared required member named `name` of trait declaration
// `trait`; duplicate required members are rejected by the trait's own unit.
uint trait_member(uint trait, uint name)
{
    uint start; uint count;
    if (trait == INVALID || !dependency_contract_owner_members(trait, start, count)) return INVALID;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint base = (start + ordinal) * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(base) == trait &&
            dependency_member_word(base + 1u) == MEMBER_TRAIT_METHOD &&
            dependency_member_word(base + 3u) == name_hash_lo[name] &&
            dependency_member_word(base + 4u) == name_hash_hi[name]) return start + ordinal;
    }
    return INVALID;
}

// Walk the call's generic scopes outward, as caller contract proofs do. Every
// accepted bound on exactly this parameter whose trait is on this page may
// contribute; two different members of the same name, or one member from two
// bounds of which one has arguments, are ambiguous. `predicate` is the bound
// that supplied it.
uint bound_member(uint function, uint parameter, uint name, out uint predicate)
{
    predicate = INVALID;
    uint count = min(compact_predicate_count[0u], gParams.hir_capacity);
    if (count == 0u) return INVALID;
    uint found = INVALID;
    uint owner = function;
    for (uint depth = 0u; depth < active_hir_count() && valid_hir(owner); depth++)
    {
        uint owner_token = hir_generic_owner_token(compact_hir_core[owner],
            compact_hir_payload[owner], token_capacity());
        if (owner_token >= token_capacity()) return INVALID;
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
            uint member = trait_member(page_trait(predicate_bound_reference[row]), name);
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
    uint total = min(compact_type_arg_count[0u], gParams.hir_capacity);
    if (range.start > total || ordinal >= range.count || range.start + ordinal >= total)
        return uint2(0u, INVALID);
    uint node = compact_type_args[range.start + ordinal].value;
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_TYPE) return uint2(0u, INVALID);
    uint anchor = compact_hir_core[node].token_start;
    if (anchor >= token_capacity()) return uint2(0u, INVALID);
    uint tag = type_expr_ref_tag[anchor];
    uint payload = type_expr_ref_payload[anchor];
    return tag >= 1u && tag <= 3u && payload != INVALID ? uint2(tag, payload) : uint2(0u, INVALID);
}

// Publish the predicate's arguments as call `call`'s context arguments for
// the trait's type parameters. False when an argument is not a checked type
// or the trait has other parameters.
bool publish_trait_arguments(uint call, uint predicate)
{
    uint count = predicate_bound_arg_count[predicate];
    uint reference = predicate_bound_reference[predicate];
    if (trait_reference_header(reference, 1u) != count ||
        trait_reference_header(reference, 2u) != 0u) return false;
    if (count == 0u) return true;
    uint rows; uint stride;
    call_context_ref_tag.GetDimensions(rows, stride);
    if (count > 31u || call >= rows / 32u) return false;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
        if (bound_argument(predicate, ordinal).x == 0u) return false;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint2 argument = bound_argument(predicate, ordinal);
        call_context_ref_tag[call * 32u + ordinal] = argument.x;
        call_context_ref_payload[call * 32u + ordinal] = argument.y;
    }
    call_context_arg_mask[call] |= (1u << count) - 1u;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint2 aliases;
    uint token = method_call_token(call, aliases);
    // A path call `P::member(...)` has no receiver value (methods/06).
    bool dotted = aliases.x == INVALID;
    if (token >= min(token_count[0u], token_capacity()) ||
        method_call_selection_owned[token] == 0u ||
        method_call_name_id[token] == INVALID ||
        (method_call_receiver_hir[token] != INVALID) != dotted) return;
    uint name = name_id_by_token[token];
    uint names; uint stride;
    name_hash_lo.GetDimensions(names, stride);
    if (name >= names) return;
    uint tag = method_call_source_ref_tag[token];
    uint payload = method_call_source_ref_payload[token];
    uint capacity;
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
    if (tag != TYPE_REF_GENERIC_PARAM || payload >= token_capacity()) return;
    uint encoded = enclosing_fn[token];
    if (encoded == 0u || !valid_hir(encoded - 1u)) return;
    uint predicate;
    uint member = bound_member(encoded - 1u, payload, name, predicate);
    if (member == INVALID) return;
    MethodCandidate summary = method_candidate[token];
    MethodCandidate candidate = method_candidate_empty();
    uint base = member * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint mode = INVALID;
    if (member != AMBIGUOUS) mode = (dependency_member_word(base + 8u) >> 28u) & 3u;
    // A path call passes every argument explicitly (receiver mode 0),
    // whatever the member's first parameter.
    if (!dotted && (mode == 0u || mode == 3u)) mode = 0u;
    else if (!dotted || (mode != 1u && mode != 2u)) mode = INVALID;
    uint library = INVALID; uint unit = INVALID; uint owner_local;
    bool owned = false;
    if (member != AMBIGUOUS)
        owned = dependency_contract_owner_identity(dependency_member_word(base), library, unit, owner_local);
    // A dotted call of a member without a self parameter (or with an
    // explicitly typed one), a path call of a self member, two bounds
    // supplying this name, or a bound whose arguments do not bind the
    // trait's parameters cannot be selected.
    if (mode != INVALID && owned && publish_trait_arguments(call, predicate))
    {
        candidate.state = METHOD_CANDIDATE_UNIQUE;
        candidate.library_id = library;
        candidate.unit_id = unit;
        candidate.deref_count = depth;
        candidate.module_preference = 0u;
        candidate.callable_kind = METHOD_CALLABLE_DEPENDENCY;
        candidate.local_index = dependency_member_word(base + 9u);
        candidate.matched_ref_tag = tag;
        candidate.matched_ref_payload = payload;
        candidate.receiver_mode = mode;
        if (predicate_bound_arg_count[predicate] != 0u)
        {
            call_context_owner_by_token[token] = call;
            if (aliases.x < token_capacity()) call_context_owner_by_token[aliases.x] = call;
            if (aliases.y < token_capacity()) call_context_owner_by_token[aliases.y] = call;
        }
    }
    else candidate.state = METHOD_CANDIDATE_INVALID;
    method_candidate_offer(summary, candidate);
    method_candidate[token] = summary;
}
