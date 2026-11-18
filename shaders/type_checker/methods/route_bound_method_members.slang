// Route bound-member calls in a standalone job's selected in-place body.
// The concrete receiver matches local implementations by canonical type
// identity. The selected method owns the resulting type/constant environment.
// Pattern traversal uses a packed child path, without per-lane arrays.
//
// This local path cannot route methods defined in another unit. A call with
// no local target, or a target requiring another generic instance, invalidates
// the in-place selection. Whole-program monomorphization keeps all frontend
// bodies symbolic and uses the program trait solver's retained evidence for
// both local and cross-unit method routes.
//
// One lane owns each call's context rows and method-callee reference.

import shared.buffers.gpu_index;
import shared.syntax.hir_records;
import shared.buffers.status;
import type_checker.methods.method_lookup;
import type_checker.methods.method_candidate;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import type_checker.canonicalization.canonical_api;
import type_checker.canonicalization.canonical_checked_rows;
import type_checker.substitution.checked_operand_ids;
import type_checker.constant_parameter_slots;
import type_checker.predicates.trait_reference;
import shared.semantics.callable_identity;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> method_call_receiver_hir;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> method_lookup_head;
StructuredBuffer<uint> method_lookup_next;
StructuredBuffer<uint> method_decl_method_row;
StructuredBuffer<uint> method_decl_name_token;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> fn_start_token_by_decl_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> interface_public_decl_index_by_hir;
RWStructuredBuffer<uint> call_dependency_generic_requirements;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_host_service;
RWStructuredBuffer<uint> call_dependency_native_abi;
StructuredBuffer<uint> predicate_method_validation_required_symbol;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;
RWStructuredBuffer<MethodCandidate> method_candidate;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> backend_call_fn_index;
RWStructuredBuffer<uint> call_context_owner_by_token;
RWStructuredBuffer<uint> call_context_arg_mask;
RWStructuredBuffer<uint> call_context_ref_tag;
RWStructuredBuffer<uint> call_context_ref_payload;
RWStructuredBuffer<uint> call_context_constant_mask;
RWStructuredBuffer<uint> call_context_constant_kind;
RWStructuredBuffer<uint> call_context_constant_payload;
RWStructuredBuffer<uint> call_context_constant_identity_mode;
RWStructuredBuffer<uint> call_context_constant_valid_mask;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_generic_claim_prefix;
StructuredBuffer<uint> call_generic_claim_scan_input;
StructuredBuffer<uint> call_const_claim_prefix;
StructuredBuffer<uint> call_const_claim_scan_input;
RWStructuredBuffer<uint> call_generic_claim_callee;
RWStructuredBuffer<uint> call_const_claim_callee;
RWStructuredBuffer<uint> call_const_claim_selected;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint REQUIRED_LOCAL = 1u;
static const uint REQUIRED_IMPORTED = 2u;
static const uint HIR_ITEM = 2u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_UNROUTED_BOUND_MEMBER = 0xffffff0eu;
// A packed child path: five bits per level, six levels.
static const uint PATH_DEPTH_LIMIT = 6u;
static const uint BIND_STEP_LIMIT = 256u;

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node < active_hir_count(); }
uint active_hir_node_count() { return active_hir_count(); }

#define LANIUS_INPLACE_WRITE_OWNER 1
#include "../closure/inplace_instance_lookup.slang"

#include "local_required_member.slang"

// The required member of call token `token`: (REQUIRED_LOCAL, its trait's
// HIR item), or (REQUIRED_IMPORTED, the trait's library and unit, the
// member's symbol) for an imported trait's member (offer_dependency_bound_members), or
// (0, ..) for any other callee.
uint4 required_member(uint token)
{
    uint library = call_dependency_library_id[token];
    if (library == INVALID)
    {
        uint trait = required_member_trait(call_fn_index[token]);
        return trait == INVALID ? uint4(0u, INVALID, INVALID, INVALID)
            : uint4(REQUIRED_LOCAL, trait, INVALID, INVALID);
    }
    MethodCandidate candidate = method_candidate[token];
    uint unit = call_dependency_unit_id[token];
    uint symbol = call_dependency_local_index[token];
    bool bound = candidate.state == METHOD_CANDIDATE_UNIQUE &&
        candidate.callable_kind == METHOD_CALLABLE_DEPENDENCY &&
        candidate.module_preference == 0u &&
        candidate.matched_ref_tag == TYPE_REF_GENERIC_PARAM &&
        candidate.library_id == library && candidate.unit_id == unit &&
        candidate.local_index == symbol;
    return bound ? uint4(REQUIRED_IMPORTED, library, unit, symbol)
        : uint4(0u, INVALID, INVALID, INVALID);
}

// Whether implementation `impl`, with method HIR `member`, implements the
// trait of `required`.
bool implements(uint impl, uint member, uint4 required)
{
    if (!valid_hir(impl)) return false;
    uint reference = predicate_bound_reference[impl];
    if (required.x == REQUIRED_LOCAL)
        return !trait_reference_is_dependency(reference) &&
            reference < min(decl_count_out[0u], gParams.n_tokens) &&
            decl_hir_node[reference] == required.y;
    if (!trait_reference_is_dependency(reference) || !valid_hir(member)) return false;
    uint paths; uint stride;
    resolved_dependency_library_id.GetDimensions(paths, stride);
    if (trait_reference_path(reference) >= paths) return false;
    uint4 identity = trait_reference_identity(reference);
    return identity.y == required.y && identity.z == required.z &&
        predicate_method_validation_required_symbol[member] == required.w;
}

// The method token of call expression `call`, or INVALID: its callee member's
// name, or the leaf of its qualified callee path `P::member` (a path span ends
// after its leaf), where mark_method_call_keys keys an associated call. A path callee is
// also read at its first segment (finalize_method_candidates owner alias) and at the callee's
// value token (project_semantic_call_facts); `aliases` are those tokens.
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

// The argument claims of call `call` bind the required member's parameters,
// which include the trait's (emit_generic_claims). A routed call has another callee,
// whose bindings are the context published here, so its claims are retired.
void retire_claims(uint call)
{
    uint start = call_arg_row_start[call];
    uint count = call_arg_row_count[call];
    if (start == INVALID) return;
    uint rows; uint claims; uint constants; uint stride;
    call_generic_claim_prefix.GetDimensions(rows, stride);
    call_generic_claim_callee.GetDimensions(claims, stride);
    call_const_claim_callee.GetDimensions(constants, stride);
    if (start > rows || count > rows - start) return;
    for (uint row = start; row < start + count; row++)
    {
        uint first = call_generic_claim_prefix[row];
        uint span = call_generic_claim_scan_input[row];
        for (uint claim = first; claim < min(first + span, claims); claim++)
            call_generic_claim_callee[claim] = INVALID;
        first = call_const_claim_prefix[row];
        span = call_const_claim_scan_input[row];
        for (uint claim = first; claim < min(first + span, constants); claim++)
        {
            call_const_claim_callee[claim] = INVALID;
            call_const_claim_selected[claim] = 0u;
        }
    }
}

// Publish the routed callee at method token `token` or an alias of it: a
// local member `selected`, or a dependency member `target` (no local callee).
// An imported trait's required member was itself a dependency callee.
void publish_callee(uint token, MethodCandidate candidate, uint selected, uint backend,
    uint3 target, uint requirements)
{
    if (token >= gParams.n_tokens) return;
    method_candidate[token] = candidate;
    call_fn_index[token] = selected;
    backend_call_fn_index[token] = backend;
    call_dependency_library_id[token] = target.x;
    call_dependency_unit_id[token] = target.y;
    call_dependency_local_index[token] = target.z;
    call_dependency_host_service[token] = INVALID;
    call_dependency_native_abi[token] = 0u;
    call_dependency_generic_requirements[token] = requirements;
}

// Whether call `call` has context rows (contextual_call_environment.slang).
bool has_context_rows(uint call)
{
    uint rows; uint stride;
    call_context_ref_tag.GetDimensions(rows, stride);
    return call < rows / 32u;
}

uint slots_mask(uint count) { return count == 32u ? 0xffffffffu : (1u << count) - 1u; }

// Validate the selected pool span and every destination before writing any
// context row. The seed already admitted the whole packet in a prior dispatch;
// this bounded check also rejects an unavailable context rather than publishing
// a callee with a partial environment. Receiver selection remains the accepted
// candidate's checked plan; transported mode equality was checked above.


uint path_index(uint path, uint level) { return (path >> (level * 5u)) & 31u; }

// The canonical node at `path` (its first `depth` levels) under `root`.
uint id_at(uint root, uint path, uint depth)
{
    uint node = root;
    for (uint level = 0u; level < depth; level++) node = ct_arg(node, path_index(path, level));
    return node;
}

// Child `index` of a checked operand, in canonical child order (a named
// type's operands; the element of an array, slice or reference).
uint2 checked_child(uint2 operand, uint index)
{
    if (operand.x != 3u || operand.y >= checked_type_capacity()) return uint2(0u, INVALID);
    uint kind = type_instance_kind[operand.y];
    uint tag = 0u; uint payload = INVALID;
    if (kind == 1u) CtCheckedRows.argument(operand.y, index, tag, payload);
    else if (index == 0u && kind >= 2u && kind <= 4u)
    {
        tag = type_instance_elem_ref_tag[operand.y];
        payload = type_instance_elem_ref_payload[operand.y];
    }
    return uint2(tag, payload);
}

// The first child of pattern node `node` at or after `from` that is an open
// record, or `arity`. slangc 2026.2 miscompiles a loop that sets a sentinel
// and breaks (AGENT_RULES 23:40), so the walk asks this helper.
uint next_open_child(uint node, uint from, uint arity)
{
    for (uint index = from; index < arity; index++)
    {
        uint child = ct_arg(node, index);
        if (!ct_is_param(child) && ct_is_record(child) && !ct_closed(child)) return index;
    }
    return arity;
}

// The slot of local parameter leaf `leaf` in its kind's numbering (type and
// constant parameters have separate slots), or INVALID.
uint leaf_slot(uint leaf, bool constant)
{
    uint tokens; uint stride;
    uint token = ct_param_token(leaf);
    if (constant)
    {
        type_const_param_slot_by_token.GetDimensions(tokens, stride);
        return token < tokens ? type_const_param_slot_by_token[token] : INVALID;
    }
    type_generic_param_slot_by_token.GetDimensions(tokens, stride);
    return token < tokens ? type_generic_param_slot_by_token[token] : INVALID;
}

// Bind parameter leaf `leaf`, child `index` of the pattern node at `path`, to
// `value`, the receiver's ID there. A slot bound before must agree by ID; a
// new one keeps the receiver's checked operand at that position in the call's
// context row of its kind and joins `bound` (x type slots, y constant slots).
bool bind_leaf(uint leaf, uint value, uint2 receiver, uint path, uint depth, uint index,
    uint call, uint slot_limit, inout uint2 bound)
{
    bool constant = ct_is_const_param(leaf);
    if (ct_is_dep_param(leaf) || !ct_closed(value) || ct_is_constant(value) != constant) return false;
    uint slot = leaf_slot(leaf, constant);
    if (slot >= slot_limit) return false;
    uint row = call * 32u + slot;
    uint bit = 1u << slot;
    if (((constant ? bound.y : bound.x) & bit) != 0u)
        return (constant
            ? ct_constant_ref(call_context_constant_kind[row], call_context_constant_payload[row])
            : ct_ref(call_context_ref_tag[row], call_context_ref_payload[row])) == value;
    uint2 operand = receiver;
    for (uint level = 0u; level < depth; level++) operand = checked_child(operand, path_index(path, level));
    operand = checked_child(operand, index);
    if (operand.x == 0u || operand.y == INVALID || ct_ref(operand.x, operand.y) != value ||
        ((operand.x & CT_CONSTANT_TAG_BIT) != 0u) != constant) return false;
    if (constant)
    {
        call_context_constant_kind[row] = operand.x & ~CT_CONSTANT_TAG_BIT;
        call_context_constant_payload[row] = operand.y;
        call_context_constant_identity_mode[row] = 0u;
        bound.y |= bit;
        return true;
    }
    call_context_ref_tag[row] = operand.x;
    call_context_ref_payload[row] = operand.y;
    bound.x |= bit;
    return true;
}

// Whether generic pattern `pattern` matches the receiver (`actual` its ID,
// `receiver` its checked operand), binding type and constant slots below
// `slot_limit`. Only open pattern nodes are visited; a closed child is
// compared by ID.
bool bind_pattern(uint pattern, uint actual, uint2 receiver, uint call, uint slot_limit,
    inout uint2 bound)
{
    if (!ct_is_record(pattern) || ct_closed(pattern)) return false;
    uint depth = 0u;
    uint path = 0u;
    uint cursor = 0u;
    bool enter = true;
    for (uint step = 0u; step < BIND_STEP_LIMIT; step++)
    {
        uint node = id_at(pattern, path, depth);
        uint other = id_at(actual, path, depth);
        uint arity = ct_arity(node);
        if (enter)
        {
            // Heads (kind, arity, type slots, words) agree: the declaration
            // of a named type.
            if (!ct_is_stored(other) || any(ct_head[node] != ct_head[other])) return false;
            for (uint index = 0u; index < arity; index++)
            {
                uint child = ct_arg(node, index);
                uint value = ct_arg(other, index);
                if (ct_is_param(child))
                {
                    if (!bind_leaf(child, value, receiver, path, depth, index, call, slot_limit, bound))
                        return false;
                }
                else if (ct_closed(child) && (child != value || !ct_is_resolved(child))) return false;
            }
        }
        uint next = next_open_child(node, cursor, arity);
        if (next < arity)
        {
            if (depth + 1u >= PATH_DEPTH_LIMIT) return false;
            uint shift = depth * 5u;
            path = (path & ~(31u << shift)) | (next << shift);
            depth++;
            cursor = 0u;
            enter = true;
            continue;
        }
        if (depth == 0u) return true;
        depth--;
        cursor = path_index(path, depth) + 1u;
        enter = false;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    // Seed validation completes in an earlier dispatch. A malformed packet
    // never publishes even an otherwise searchable prefix of its bindings.
    if (status[STATUS_OK_SLOT] == 0u) return;
    // One thread per call expression: calls own their context rows by HIR
    // node, and a receiver's HIR parent is not its member.
    uint node = linear_thread_id_2d(dtid, 65535u, 256u);
    uint2 aliases;
    uint token = method_call_token(node, aliases);
    // A dotted call has a receiver value; a path call has none (mark_method_call_keys).
    if (token >= min(token_count[0u], gParams.n_tokens) ||
        (method_call_receiver_hir[token] == INVALID) != (aliases.x != INVALID) ||
        method_call_name_id[token] == INVALID) return;
    uint4 required = required_member(token);
    if (required.x == 0u) return;
    // An original job routes only the bodies it instantiates in place
    // (select_inplace_instances); every other receiver is a parameter.
    uint in_place_owner = enclosing_fn[token] - 1u;
    if (inplace_instance(in_place_owner) == INPLACE_NONE) return;
    uint tag = method_call_receiver_ref_tag[token];
    uint payload = method_call_receiver_ref_payload[token];
    if (tag == TYPE_REF_GENERIC_PARAM || tag == 0u || payload == INVALID) return;
    uint2 receiver = uint2(tag, payload);
    uint call = has_context_rows(node) ? node : INVALID;
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    uint spare = CT_NONE;
    uint actual = CT_UNKNOWN;
    MethodReceiverHead head;
    uint selected = INVALID;
    uint selected_row = INVALID;
    bool selected_generic = false;
    uint matches = 0u;
    // Context rows written by generic candidates, and the bindings published
    // (x type slots, y constant slots).
    uint2 written = uint2(0u, 0u);
    uint2 published = uint2(0u, 0u);
    bool rebound = false;
    if (count != 0u && method_receiver_head<ScopedCheckedTypeGraph>(tag, payload,
        checked_type_capacity(), gParams.n_tokens, head))
    {
        uint name_id = method_call_name_id[token];
        uint link = method_lookup_head[method_lookup_bucket(head, name_id, count)];
        // Step 0 interns the receiver; then the chain, then the selected
        // generic candidate once more: its bindings are the ones left in the
        // context rows. One interning site and one binding site.
        [loop]
        for (uint visited = 0u; visited <= count + 1u; visited++)
        {
            uint row = INVALID;
            uint candidate = INVALID;
            uint impl = INVALID;
            uint2 operand = receiver;
            if (visited != 0u)
            {
                if (link != 0u)
                {
                    row = link - 1u;
                    if (row >= count) { matches = 2u; break; }
                    link = method_lookup_next[row];
                }
                else if (matches == 1u && selected_generic) { row = selected_row; rebound = true; }
                else break;
                HirMethodCore core = compact_method_cores[row];
                candidate = core.name_token;
                impl = core.impl_node;
                if (candidate >= gParams.n_tokens || method_decl_name_id[candidate] != name_id ||
                    !implements(impl, core.node, required)) continue;
                operand = uint2(method_decl_receiver_ref_tag[candidate],
                    method_decl_receiver_ref_payload[candidate]);
            }
            uint id = ct_intern_checked<CtCheckedRows>(operand.x, operand.y, spare);
            if (visited == 0u) { actual = id; continue; }
            uint pattern = id;
            uint parameters = compact_generic_param_ranges[impl].count;
            bool generic = parameters != 0u;
            bool matched = false;
            if (!generic) matched = ct_closed(actual) && ct_is_resolved(pattern) && pattern == actual;
            else
            {
                uint member = fn_hir_by_decl_token[candidate];
                uint2 bound = uint2(0u, 0u);
                // Each parameter binds one slot of its kind.
                matched = ct_closed(actual) && call != INVALID && parameters < 32u && valid_hir(member) &&
                    compact_generic_param_ranges[member].count == 0u &&
                    bind_pattern(pattern, actual, receiver, call, parameters, bound) &&
                    countbits(bound.x) + countbits(bound.y) == parameters;
                written |= bound;
                if (rebound) { published = matched ? bound : uint2(0u, 0u); break; }
            }
            if (!matched) continue;
            if (selected != candidate) matches++;
            selected = candidate;
            selected_row = row;
            selected_generic = generic;
        }
    }
    // The accepted selection and its callee are one fact for call artifacts.
    // An imported trait's member was verified as the candidate above.
    MethodCandidate candidate = method_candidate[token];
    bool accepted = candidate.state == METHOD_CANDIDATE_UNIQUE &&
        (required.x == REQUIRED_IMPORTED || (candidate.callable_kind == METHOD_CALLABLE_LOCAL &&
         candidate.local_index == call_fn_index[token]));
    uint3 target = uint3(INVALID, INVALID, INVALID);
    bool bindings = any(published != 0u);
    bool routed = accepted && matches == 1u && (!selected_generic || bindings);
    // The routed callee owns the call's context: a generic one its bindings,
    // a nongeneric one none (the trait's arguments bound the required
    // member's parameters, offer_bound_method_members). Rows written for other candidates
    // hold no binding.
    if (call != INVALID && (any(written != 0u) || routed))
    {
        call_context_arg_mask[call] = routed
            ? (selected_generic ? published.x : 0u) : call_context_arg_mask[call] & ~written.x;
        uint constants = routed
            ? (selected_generic ? published.y : 0u) : call_context_constant_mask[call] & ~written.y;
        call_context_constant_mask[call] = constants;
        call_context_constant_valid_mask[call] = routed
            ? constants : call_context_constant_valid_mask[call] & ~written.y;
        if (routed)
        {
            call_context_owner_by_token[token] = call;
            if (aliases.x < gParams.n_tokens) call_context_owner_by_token[aliases.x] = call;
            if (aliases.y < gParams.n_tokens) call_context_owner_by_token[aliases.y] = call;
        }
    }
    // An in-place body whose call finds no member in this unit, or a generic
    // implementation's member (an instance of its own), stays a template:
    // whole-program projection routes it using retained solver evidence.
    if (!routed || selected_generic)
    {
        uint ignored;
        InterlockedOr(instance_inplace_owner[in_place_owner], INPLACE_FAILED, ignored);
        if (!routed) return;
    }
    if (matches != 1u || (selected_generic && !bindings))
    {
        record_min_token_error(status, token, ERR_CALL_MISMATCH, CALL_MISMATCH_UNROUTED_BOUND_MEMBER);
        return;
    }
    if (!routed) return;
    retire_claims(node);
    candidate.matched_ref_tag = tag;
    candidate.matched_ref_payload = payload;
    uint backend = INVALID;
    {
        // The routed member is local to this unit.
        candidate.callable_kind = METHOD_CALLABLE_LOCAL;
        candidate.library_id = INVALID;
        candidate.unit_id = INVALID;
        candidate.local_index = selected;
        uint start = fn_start_token_by_decl_token[selected];
        backend = start < gParams.n_tokens ? start : selected;
    }
    uint requirements = 0u;
    publish_callee(token, candidate, selected, backend, target, requirements);
    if (aliases.x != token) publish_callee(aliases.x, candidate, selected, backend, target, requirements);
    if (aliases.y != token && aliases.y != aliases.x)
        publish_callee(aliases.y, candidate, selected, backend, target, requirements);
}
