// Route bound-member calls of the selected replay body (07a) to the member of
// the implementation that the now-concrete receiver selects.
//
// Body specialization has substituted the call's accepted receiver: the
// receiver value of `value.member(...)`, or the parameter `P` of a static
// `P::member(...)`. The required member names its trait; a candidate is an implementation method of
// that trait with the same name whose receiver pattern matches the receiver.
// Types compare by canonical ID (docs/canonical-type-ids.md). A replay
// re-arms every row before the match passes (03_rearm), so the receiver and
// each pattern are interned here, on demand. Replay rewrites only the rows of
// the selected environment; when that is a generic impl's own method, its
// rewritten header has another head than any receiver in the body (the
// lookup chain is keyed by head), except for a blanket impl, which is not
// routed.
//
// A nongeneric implementation matches when its pattern is the receiver. A
// generic one matches when its type parameters bind so that the pattern is the
// receiver; the routed call then owns that environment, and each binding is
// published as the call's context argument (contextual_call_environment.slang)
// in the receiver's own checked spelling at the parameter's position, which is
// what host retention reads to replay the routed body. Bindings are found
// without a stack or local array: a walk over the pattern's open nodes
// re-descends from the root along a packed child path, and the call's context
// rows hold the bindings until the mask publishes them. Constant parameters,
// a parameter that the receiver does not bind and methods with parameters of
// their own are not routed; neither is a receiver with no match.
// Outside replay every accepted receiver of these calls is still a parameter,
// so nothing is routed and the enclosing body stays a template.
//
// A bound on an imported trait selects that trait's required member by its
// portable identity (dependencies/15b: a dependency candidate of module
// preference 0, which no implementation candidate has). An implementation of
// that trait in this unit implements it by the trait's library and unit and
// the required member's symbol (predicates/01f2), and the routed call becomes
// a local one.
//
// An implementation outside this unit has no candidate here. In replay, the
// instance's program evidence names it (body_impl_bindings.slang): the
// implementation that proved the bound on the parameter's binding slot, keyed
// by the required member's symbol and its trait's unit. The call then becomes
// a dependency call of that implementation's member.
//
// One thread per call expression (HIR domain): the call owns the context rows,
// and its callee member, or the leaf of its callee path `P::member` for a
// static member, names the method token.

import gpu_index;
import hir_records;
import status;
import type_checker.methods.lookup;
import type_checker.methods.candidate;
import type_checker.checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;
import type_checker.predicates.trait_reference;

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
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> fn_start_token_by_decl_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> interface_public_decl_index_by_hir;
StructuredBuffer<uint4> body_specialization_inputs;
RWStructuredBuffer<uint> call_dependency_generic_requirements;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_host_service;
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

#include "../type/instances/body_specialization_owner.slang"
#include "../type/instances/body_impl_bindings.slang"

// Required members publish signature metadata without a lookup row (02_collect).
uint required_member_trait(uint target)
{
    if (target >= gParams.n_tokens || method_decl_method_row[target] != INVALID) return INVALID;
    uint member = fn_hir_by_decl_token[target];
    if (!valid_hir(member)) return INVALID;
    uint trait = predicate_method_contract_owner_hir[member];
    return valid_hir(trait) && compact_hir_core[trait].kind == HIR_ITEM &&
        compact_hir_payload[trait].a == HIR_ITEM_KIND_TRAIT ? trait : INVALID;
}

// The required member of call token `token`: (REQUIRED_LOCAL, its trait's
// HIR item), or (REQUIRED_IMPORTED, the trait's library and unit, the
// member's symbol) for an imported trait's member (dependencies/15b), or
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

// The implementation member (library, unit, native symbol) outside this unit
// that the replayed instance's evidence selected for the bound that offered
// `candidate` (07a, 15b) on its parameter, for call token `token`.
bool external_target(uint token, uint4 required, MethodCandidate candidate, out uint3 target)
{
    target = uint3(INVALID, INVALID, INVALID);
    if (candidate.matched_ref_tag != TYPE_REF_GENERIC_PARAM) return false;
    uint tokens; uint stride;
    type_generic_param_slot_by_token.GetDimensions(tokens, stride);
    uint parameter = candidate.matched_ref_payload;
    uint slot = parameter < tokens ? type_generic_param_slot_by_token[parameter] : INVALID;
    uint encoded = enclosing_fn[token];
    if (slot == INVALID || encoded == 0u || !valid_hir(encoded - 1u)) return false;
    uint instance = body_specialization_entry_for_owner(encoded - 1u);
    if (instance == INVALID) return false;
    uint symbol = required.w;
    uint2 trait_unit = required.yz;
    if (required.x == REQUIRED_LOCAL)
    {
        uint member = fn_hir_by_decl_token[call_fn_index[token]];
        if (!valid_hir(member)) return false;
        symbol = 0x80000000u | member;
        trait_unit = uint2(INVALID, INVALID);
    }
    return body_impl_binding(instance, slot, symbol, trait_unit, target) &&
        target.x != INVALID && target.y != INVALID && target.z != INVALID;
}

// The method token of call expression `call`, or INVALID: its callee member's
// name, or the leaf of its qualified callee path `P::member` (a path span ends
// after its leaf), where methods/06 keys an associated call. A path callee is
// also read at its first segment (methods/08 owner alias) and at the callee's
// value token (semantic/artifact/00_calls); `aliases` are those tokens.
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
// which include the trait's (calls/03a1). A routed call has another callee,
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
    uint3 target)
{
    if (token >= gParams.n_tokens) return;
    method_candidate[token] = candidate;
    call_fn_index[token] = selected;
    backend_call_fn_index[token] = backend;
    call_dependency_library_id[token] = target.x;
    call_dependency_unit_id[token] = target.y;
    call_dependency_local_index[token] = target.z;
    call_dependency_host_service[token] = INVALID;
    call_dependency_generic_requirements[token] = 0u;
}

// Whether call `call` has context rows (contextual_call_environment.slang).
bool has_context_rows(uint call)
{
    uint rows; uint stride;
    call_context_ref_tag.GetDimensions(rows, stride);
    return call < rows / 32u;
}

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

// Bind parameter leaf `leaf`, child `index` of the pattern node at `path`, to
// `value`, the receiver's ID there. A slot bound before must agree by ID; a
// new one keeps the receiver's checked operand at that position in the call's
// context row and joins `bound`.
bool bind_leaf(uint leaf, uint value, uint2 receiver, uint path, uint depth, uint index,
    uint call, uint slot_limit, inout uint bound)
{
    if (!ct_is_type_param(leaf) || ct_is_dep_param(leaf) || !ct_closed(value) ||
        ct_is_constant(value)) return false;
    uint tokens; uint stride;
    type_generic_param_slot_by_token.GetDimensions(tokens, stride);
    uint token = ct_param_token(leaf);
    uint slot = token < tokens ? type_generic_param_slot_by_token[token] : INVALID;
    if (slot >= slot_limit) return false;
    uint row = call * 32u + slot;
    if ((bound & (1u << slot)) != 0u)
        return ct_ref(call_context_ref_tag[row], call_context_ref_payload[row]) == value;
    uint2 operand = receiver;
    for (uint level = 0u; level < depth; level++) operand = checked_child(operand, path_index(path, level));
    operand = checked_child(operand, index);
    if (operand.x == 0u || operand.y == INVALID || ct_ref(operand.x, operand.y) != value) return false;
    call_context_ref_tag[row] = operand.x;
    call_context_ref_payload[row] = operand.y;
    bound |= 1u << slot;
    return true;
}

// Whether generic pattern `pattern` matches the receiver (`actual` its ID,
// `receiver` its checked operand), binding type slots below `slot_limit`.
// Only open pattern nodes are visited; a closed child is compared by ID.
bool bind_pattern(uint pattern, uint actual, uint2 receiver, uint call, uint slot_limit,
    inout uint bound)
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
    // One thread per call expression: calls own their context rows by HIR
    // node, and a receiver's HIR parent is not its member.
    uint node = linear_thread_id_2d(dtid, 65535u, 256u);
    uint2 aliases;
    uint token = method_call_token(node, aliases);
    // A dotted call has a receiver value; a path call has none (methods/06).
    if (token >= min(token_count[0u], gParams.n_tokens) ||
        (method_call_receiver_hir[token] == INVALID) != (aliases.x != INVALID) ||
        method_call_name_id[token] == INVALID) return;
    uint4 required = required_member(token);
    if (required.x == 0u) return;
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
    // Context rows written by generic candidates, and the bindings published.
    uint written = 0u;
    uint published = 0u;
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
                uint bound = 0u;
                matched = ct_closed(actual) && call != INVALID && parameters < 32u && valid_hir(member) &&
                    compact_generic_param_ranges[member].count == 0u &&
                    bind_pattern(pattern, actual, receiver, call, parameters, bound) &&
                    bound == (1u << parameters) - 1u;
                written |= bound;
                if (rebound) { published = matched ? bound : 0u; break; }
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
    // With no implementation in this unit, the one the instance's evidence
    // selected elsewhere.
    uint3 target = uint3(INVALID, INVALID, INVALID);
    bool external = matches == 0u && accepted && external_target(token, required, candidate, target);
    bool routed = accepted && (external || (matches == 1u && (!selected_generic || published != 0u)));
    // The routed callee owns the call's context: a generic one its bindings,
    // a nongeneric one none (the trait's arguments bound the required
    // member's parameters, methods/07a). Rows written for other candidates
    // hold no binding.
    if (call != INVALID && (written != 0u || routed))
    {
        call_context_arg_mask[call] = routed
            ? (selected_generic ? published : 0u) : call_context_arg_mask[call] & ~written;
        if (routed && selected_generic)
        {
            call_context_owner_by_token[token] = call;
            if (aliases.x < gParams.n_tokens) call_context_owner_by_token[aliases.x] = call;
            if (aliases.y < gParams.n_tokens) call_context_owner_by_token[aliases.y] = call;
        }
    }
    if (!external && (matches != 1u || (selected_generic && published == 0u)))
    {
        record_min_token_error(status, token, ERR_CALL_MISMATCH, CALL_MISMATCH_UNROUTED_BOUND_MEMBER);
        return;
    }
    if (!routed) return;
    retire_claims(node);
    candidate.matched_ref_tag = tag;
    candidate.matched_ref_payload = payload;
    uint backend = INVALID;
    if (external)
    {
        // The evidence's implementation member, in its own unit.
        candidate.callable_kind = METHOD_CALLABLE_DEPENDENCY;
        candidate.library_id = target.x;
        candidate.unit_id = target.y;
        candidate.local_index = target.z;
        selected = INVALID;
    }
    else
    {
        // The routed member is local to this unit.
        candidate.callable_kind = METHOD_CALLABLE_LOCAL;
        candidate.library_id = INVALID;
        candidate.unit_id = INVALID;
        candidate.local_index = selected;
        uint start = fn_start_token_by_decl_token[selected];
        backend = start < gParams.n_tokens ? start : selected;
    }
    publish_callee(token, candidate, selected, backend, target);
    if (aliases.x != token) publish_callee(aliases.x, candidate, selected, backend, target);
    if (aliases.y != token && aliases.y != aliases.x)
        publish_callee(aliases.y, candidate, selected, backend, target);
}
