// Bound-directed generic call inference (docs/compiler-generic-types.md,
// "Bound-directed generic call inference"). One lane per call of an imported
// free function that still has an unbound type parameter. For each bound
// `P: Tr<A1..An>` of the callee, in declaration order, whose subject P is
// bound to a closed type:
//
// 1. the implementations of Tr whose subject matches P's binding are counted
//    over the tables of bound_tables.slang (an implementation repeated on
//    several dependency pages counts once; a row without a canonical
//    subject counts as a candidate of its own);
// 2. only when exactly one matches, its trait arguments under the binding of
//    its own parameters must be closed, and A1..An are matched against them;
// 3. the resulting bindings are published as the call's context, where every
//    slot an explicit argument, an argument claim or an earlier context
//    already binds must agree, so a conflicting fact rejects the whole
//    publication and the call keeps its existing diagnostic.
//
// Implementation prerequisites (`where` clauses of the implementation) are
// not consulted: they cannot add a candidate, and program evidence still
// checks the selected implementation. Rounds repeat until nothing changes,
// so a binding inferred here can feed the next call's argument claims.
import hir_records;
import status;
import type_checker.mutable_checked_type_graph;
import type_checker.calls.claim_lookup;
import type_checker.calls.claim_reference;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.match.ct_match;
import type_checker.match.ct_context_publish;
import type_checker.calls.bound_tables;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> call_dependency_generic_requirements;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;
// The bounds one callee may have; later bounds infer nothing.
static const uint PREDICATE_LIMIT = 64u;
// Steps of one bound: one per implementation of its trait, one per trait
// argument, the matches and the publisher's requests.
static const uint WORK_LIMIT = 2048u + CT_PUBLISH_REQUEST_LIMIT;

static const uint PHASE_BINDING = 0u;
static const uint PHASE_SELECT = 1u;
static const uint PHASE_IMPLEMENTATION = 2u;
static const uint PHASE_ARGUMENTS = 3u;
static const uint PHASE_CALLEE = 4u;
static const uint PHASE_PUBLISH = 5u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_node(uint node) { return node < hir_count(); }
bool valid_token(uint token) { return token < gParams.n_tokens; }

// The token that keys a call's claims (as 03a7_validate_required_generics).
uint callee_token_for_hir_call(uint call)
{
    uint callee = compact_hir_payload[call].a;
    if (valid_node(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR)
    {
        uint member = compact_hir_payload[callee].c;
        return valid_token(member) ? member : INVALID;
    }
    uint call_token = compact_hir_core[call].token_start;
    if (!valid_node(callee)) return valid_token(call_token) ? call_token : INVALID;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token])) return call_token;
    uint token = compact_hir_payload[callee].d;
    if (!valid_token(token)) token = compact_hir_core[callee].token_start;
    if (!valid_token(token)) token = call_token;
    return valid_token(token) ? token : INVALID;
}

uint claim_count()
{
    uint base = max(gParams.n_tokens, gParams.n_hir_nodes);
    uint capacity = base > 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER
        ? 0xffffffffu : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
    return min(call_generic_claim_count_out[0u], capacity);
}

// The first concrete argument claim of (callee, slot).
bool argument_claim(uint callee, uint slot, out uint tag, out uint payload)
{
    tag = 0u; payload = INVALID;
    uint count = claim_count();
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    uint found = INVALID;
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) break;
        if (call_generic_claim_callee[row] == callee && call_generic_claim_slot[row] == slot &&
            checked_claim_reference(call_generic_claim_ref_tag[row], call_generic_claim_ref_payload[row]))
            found = min(found, row);
        link = call_generic_claim_lookup_next[row];
    }
    if (found == INVALID) return false;
    tag = call_generic_claim_ref_tag[found];
    payload = call_generic_claim_ref_payload[found];
    return true;
}

// The facts that bind a call's type slot before this pass: its explicit
// argument, else its argument claim.
struct BoundClaims : ICtClaims
{
    static bool claim(uint token, uint slot, out uint tag, out uint payload)
    {
        if (checked_explicit_environment_argument(0x80000000u | token, slot, tag, payload)) return true;
        return argument_claim(token, slot, tag, payload);
    }
}

// The operand that binds type slot `slot` of the call, from any source.
bool slot_binding(uint callee, uint slot, out uint2 operand)
{
    uint tag; uint payload;
    bool bound = BoundClaims.claim(callee, slot, tag, payload) ||
        checked_context_environment_argument(0x80000000u | callee, slot, tag, payload);
    operand = bound ? uint2(tag, payload) : uint2(0u, INVALID);
    return bound && tag != 0u && payload != INVALID;
}

uint pair_get(uint4 low, uint4 high, uint index)
{
    uint4 part = index < 4u ? low : high;
    uint lane = index & 3u;
    return lane == 0u ? part.x : lane == 1u ? part.y : lane == 2u ? part.z : part.w;
}

void pair_set(inout uint4 low, inout uint4 high, uint index, uint value)
{
    uint lane = index & 3u;
    uint4 part = index < 4u ? low : high;
    part = uint4(lane == 0u ? value : part.x, lane == 1u ? value : part.y,
        lane == 2u ? value : part.z, lane == 3u ? value : part.w);
    if (index < 4u) low = part;
    else high = part;
}

// Mode 0: one root, an implementation subject against the bound's subject.
// Mode 1: the bound's arguments against the selected implementation's.
struct BoundRoots : ICtRoots
{
    uint mode;
    uint pattern;
    uint actual;
    uint predicate;
    uint arguments;
    uint4 low;
    uint4 high;
    uint count() { return mode == 0u ? 1u : arguments; }
    [mutating] bool root(uint root, out uint pattern_out, out uint actual_out, out bool slice)
    {
        slice = false;
        pattern_out = mode == 0u ? pattern
            : bound_predicate_rows[predicate * BOUND_ROW_WORDS + 9u + root];
        actual_out = mode == 0u ? actual : pair_get(low, high, root);
        return true;
    }
}

// The next implementation row of the bound's trait and arity at or after
// `cursor`, or INVALID.
uint next_implementation(uint cursor, uint predicate)
{
    uint base = predicate * BOUND_ROW_WORDS;
    uint3 trait = uint3(bound_predicate_rows[base + 5u], bound_predicate_rows[base + 6u],
        bound_predicate_rows[base + 7u]);
    uint arguments = bound_predicate_rows[base + 8u];
    uint count = bound_row_count(BOUND_COUNT_IMPLEMENTATIONS);
    for (uint row = cursor; row < count; row++)
    {
        uint at = row * BOUND_ROW_WORDS;
        if (bound_implementation_rows[at] == trait.x && bound_implementation_rows[at + 1u] == trait.y &&
            bound_implementation_rows[at + 2u] == trait.z && bound_implementation_rows[at + 7u] == arguments)
            return row;
    }
    return INVALID;
}

uint3 implementation_identity(uint row)
{
    uint at = row * BOUND_ROW_WORDS;
    return uint3(bound_implementation_rows[at + 3u], bound_implementation_rows[at + 4u],
        bound_implementation_rows[at + 5u]);
}

uint implementation_subject(uint row) { return bound_implementation_rows[row * BOUND_ROW_WORDS + 6u]; }

// The next bound of the callee after declaration index `after` (INVALID: the
// first), or INVALID. Repeated rows of one bound share its index.
uint next_predicate(uint3 owner, uint after)
{
    uint count = bound_row_count(BOUND_COUNT_PREDICATES);
    uint best = INVALID;
    uint best_key = INVALID;
    for (uint row = 0u; row < count; row++)
    {
        uint at = row * BOUND_ROW_WORDS;
        if (bound_predicate_rows[at] != owner.x || bound_predicate_rows[at + 1u] != owner.y ||
            bound_predicate_rows[at + 2u] != owner.z) continue;
        uint key = bound_predicate_rows[at + 3u];
        if ((after != INVALID && key <= after) || key >= best_key) continue;
        best = row;
        best_key = key;
    }
    return best;
}

// The call owns its published context, through the callee token and, for a
// call that is not dotted, its head and call tokens (as 08a).
void publish_owner(uint call, uint callee)
{
    call_context_owner_by_token[callee] = call;
    uint node = compact_hir_payload[call].a;
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_MEMBER_EXPR)
    {
        uint head = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
        uint call_token = compact_hir_core[call].token_start;
        if (valid_token(head)) call_context_owner_by_token[head] = call;
        if (valid_token(call_token)) call_context_owner_by_token[call_token] = call;
    }
}

// Infer from bound `predicate` of the call's callee; true when the call's
// context changed.
bool infer_from_bound(uint call, uint callee, uint predicate, inout CtSpare spare)
{
    uint base = predicate * BOUND_ROW_WORDS;
    uint2 operand;
    if (!slot_binding(callee, bound_predicate_rows[base + 4u], operand)) return false;
    uint arguments = bound_predicate_rows[base + 8u];
    SourceSlots slots;
    BoundRoots roots;
    roots.mode = 0u;
    roots.pattern = CT_UNKNOWN;
    roots.actual = CT_UNKNOWN;
    roots.predicate = predicate;
    roots.arguments = arguments;
    roots.low = uint4(CT_NONE, CT_NONE, CT_NONE, CT_NONE);
    roots.high = roots.low;
    uint phase = PHASE_BINDING;
    uint cursor = 0u;
    uint candidate = INVALID;
    uint chosen = INVALID;
    uint implementation_env = CT_NONE;
    uint ordinal = 0u;
    uint env = CT_NONE;
    uint count_mask = 0u;
    uint3 interned = uint3(0u, INVALID, CT_NONE);
    // One site each for the interner (the subject's binding, then the
    // publisher's requests), the matcher, the substitution and the publisher.
    [loop]
    for (uint work = 0u; work < WORK_LIMIT; work++)
    {
        if (operand.x != 0u)
        {
            uint id = ct_intern_checked<CtMutableRows>(operand.x, operand.y, spare.record);
            if (phase == PHASE_BINDING)
            {
                // An open binding (inside a generic body) selects nothing.
                if (!ct_closed(id) || ct_is_constant(id)) return false;
                roots.actual = id;
                operand = uint2(0u, INVALID);
                phase = PHASE_SELECT;
                continue;
            }
            // A prior that has no ID agrees with no binding.
            if (!ct_is_resolved(id)) return false;
            interned = uint3(operand, id);
            operand = uint2(0u, INVALID);
        }
        if (phase == PHASE_SELECT)
        {
            candidate = next_implementation(cursor, predicate);
            if (candidate == INVALID)
            {
                if (chosen == INVALID || !ct_is_resolved(implementation_subject(chosen))) return false;
                phase = PHASE_IMPLEMENTATION;
            }
            else
            {
                cursor = candidate + 1u;
                // A row without a canonical subject may match any subject.
                if (!ct_is_resolved(implementation_subject(candidate)))
                {
                    if (chosen != INVALID && any(implementation_identity(chosen) != implementation_identity(candidate)))
                        return false;
                    chosen = candidate;
                    continue;
                }
            }
        }
        if (phase == PHASE_SELECT || phase == PHASE_IMPLEMENTATION || phase == PHASE_CALLEE)
        {
            roots.mode = phase == PHASE_CALLEE ? 1u : 0u;
            roots.pattern = implementation_subject(phase == PHASE_SELECT ? candidate : chosen);
            uint matched = ct_match_roots<SourceSlots, BoundRoots>(slots, roots, CT_NONE,
                phase != PHASE_SELECT, spare, count_mask);
            if (phase == PHASE_SELECT)
            {
                if (matched != CT_MATCH_OK) continue;
                if (chosen != INVALID && any(implementation_identity(chosen) != implementation_identity(candidate)))
                    return false;
                chosen = candidate;
                continue;
            }
            if (!ct_is_record(matched)) return false;
            if (phase == PHASE_IMPLEMENTATION)
            {
                implementation_env = matched;
                phase = PHASE_ARGUMENTS;
                continue;
            }
            env = matched;
            phase = PHASE_PUBLISH;
        }
        if (phase == PHASE_ARGUMENTS)
        {
            uint term = bound_implementation_rows[chosen * BOUND_ROW_WORDS + 8u + ordinal];
            uint closed = ct_subst<SourceSlots>(slots, implementation_env, term, true, spare);
            // An implementation parameter its subject does not bind leaves
            // the argument open: nothing is selected.
            if (!ct_closed(closed) || ct_is_constant(closed)) return false;
            pair_set(roots.low, roots.high, ordinal, closed);
            ordinal++;
            if (ordinal >= arguments) phase = PHASE_CALLEE;
            continue;
        }
        if (phase != PHASE_PUBLISH) return false;
        uint3 words = ct_words(env);
        bool changed;
        uint2 request;
        uint outcome = ct_publish_context_changes<BoundClaims>(call, callee, env, words.y, words.z,
            count_mask, CT_PUBLISH_ADMIT | CT_PUBLISH_TYPE_PRIORS | CT_PUBLISH_CLAIMS, interned,
            request, changed);
        if (outcome == CT_PUBLISH_INTERN) { operand = request; continue; }
        if (outcome == CT_PUBLISH_CAPACITY) record_min_token_error(status, callee, 6u, 0x474e0001u);
        if (outcome != CT_PUBLISHED) return false;
        publish_owner(call, callee);
        return changed;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return;
    // Incomplete tables could hide a second implementation.
    if (bound_inference_counts[BOUND_COUNT_OVERFLOW] != 0u) return;
    uint callee = callee_token_for_hir_call(call);
    if (!valid_token(callee) || call_intrinsic_tag[callee] != 0u ||
        call_dependency_library_id[callee] == INVALID) return;
    // Free functions only: a dotted call's bounds include its impl's.
    uint callee_node = compact_hir_payload[call].a;
    if (valid_node(callee_node) && compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR) return;
    uint types = min(call_dependency_generic_requirements[callee] & 0xffffu, 32u);
    bool open = false;
    for (uint slot = 0u; slot < types; slot++)
    {
        uint2 operand;
        if (!slot_binding(callee, slot, operand)) open = true;
    }
    if (!open) return;
    uint3 owner = uint3(call_dependency_library_id[callee], call_dependency_unit_id[callee],
        call_dependency_local_index[callee]);
    CtSpare spare = ct_spare_none();
    bool changed = false;
    uint after = INVALID;
    for (uint step = 0u; step < PREDICATE_LIMIT; step++)
    {
        uint predicate = next_predicate(owner, after);
        if (predicate == INVALID) break;
        after = bound_predicate_rows[predicate * BOUND_ROW_WORDS + 3u];
        if (infer_from_bound(call, callee, predicate, spare)) changed = true;
    }
    if (changed) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}
