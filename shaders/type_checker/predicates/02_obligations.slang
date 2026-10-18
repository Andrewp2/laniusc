// Validate trait obligations using complete ordered type graphs and accepted
// call environments. Concrete impl keys share the same graph equality/hash
// contract as ordinary generic calls; up to 32 trait arguments are supported.

import hir_records;
import type_checker.type.instances.generic_param_lookup;
import fixed.key;
import fixed.compact_method;
import hir_expr_semantics;
import range_query;
import status;
import type_checker.predicates.owner_lookup;
import type_checker.predicates.impl_lookup;
import type_checker.predicates.trait_reference;
import type_checker.calls.checked_call_type_graph;
import type_checker.predicates.scalar_subject;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
    uint dependency_interfaces_present;
    uint retain_callable_owners;
    // Private original admission uses 1; an accepted replay request uses 2.
    // Both produce unpublished objects. Unknown modes stay strict.
    uint trait_obligation_mode;
    uint authorized_replay_callable;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_type_code_by_name_id;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
// Exact lexical callable ownership, also retained into CheckedCallOwner.
// A nearest generic owner cannot distinguish sibling methods in one impl.
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_lookup_state;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> predicate_bound_arg_count;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint> predicate_owner_lookup_head;
StructuredBuffer<uint> predicate_owner_lookup_next;
StructuredBuffer<uint> predicate_impl_lookup_head;
StructuredBuffer<uint> predicate_impl_lookup_next;
#if defined(LANIUS_OBLIGATION_COUNT_PASS)
RWStructuredBuffer<uint> predicate_obligation_count_by_call;
#else
StructuredBuffer<uint> predicate_obligation_count_by_call;
StructuredBuffer<uint> predicate_obligation_prefix_by_call;
StructuredBuffer<uint> predicate_obligation_pair_total;
#endif

RWStructuredBuffer<uint> status;

#include "../type/instances/lexical_parameter_lookup.slang"

static const uint INVALID = 0xffffffffu;

static const uint ERR_TRAIT_BOUND_UNSATISFIED = 13u;
static const uint ERR_TRAIT_BOUND_AMBIGUOUS = 14u;
static const uint ERR_INVALID_TRAIT_IMPLEMENTATION = 17u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;



static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_INVALID_SUBJECT = 1u;
static const uint PREDICATE_STATUS_BOUND_NOT_TRAIT = 2u;
static const uint PREDICATE_STATUS_INVALID_ARG = 4u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_UNSATISFIED_BOUND = 9u;
static const uint PREDICATE_STATUS_AMBIGUOUS_BOUND = 10u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH = 11u;
static const uint PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE = 12u;
static const uint PREDICATE_STATUS_BOUND_ARITY_MISMATCH = 13u;
static const uint PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE = 14u;
static const uint PREDICATE_STATUS_INVALID_IMPL_ARG = 15u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND = 18u;
static const uint PREDICATE_STATUS_OVERLAPPING_IMPL = 19u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW = 21u;
static const uint PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION = 22u;
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH = 25u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW = 27u;
static const uint PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG = 28u;
static const uint PREDICATE_STATUS_UNSUPPORTED_CONST_TRAIT = 37u;
static const uint PREDICATE_STATUS_UNCONSTRAINED_IMPL_PARAMETER = 38u;
static const uint PREDICATE_STATUS_IMPL_HEAD_WORK_LIMIT = 39u;

static const uint PREDICATE_OBLIGATION_WINDOW = 32u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> predicate_trait_impl_trait_type_node;
#include "type_roots.slang"
#if defined(LANIUS_BODY_OBLIGATION_VALIDATE_PASS)
// Body roots have already received their environment; a call environment is
// neither needed nor valid at this phase.
typedef ScopedCheckedTypeGraph PredicateTypeGraph;
#else
typedef ScopedCheckedCallTypeGraph PredicateTypeGraph;
#endif

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_sorted_predicate_count()
{
    return min(gParams.n_hir_nodes, compact_predicate_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint canonical_function_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (node >= count)
        return INVALID;
    return hir_generic_owner_token(compact_hir_core[node], compact_hir_payload[node],
        gParams.n_tokens);
}

uint first_named_bound_arg_token_after_bound(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint bound_token = compact_hir_core[node].token_start;
    if (!valid_token(bound_token))
        return INVALID;

    uint candidate = bound_token + 1u;
    if (candidate >= bound_token && valid_token(candidate) && name_id_by_token[candidate] != INVALID)
        return candidate;

    candidate = bound_token + 2u;
    if (candidate >= bound_token && valid_token(candidate) && name_id_by_token[candidate] != INVALID)
        return candidate;

    candidate = bound_token + 3u;
    return candidate >= bound_token &&
           valid_token(candidate) &&
           name_id_by_token[candidate] != INVALID
        ? candidate
        : INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint call_hir = call_node;
    uint compact_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (call_hir == INVALID || call_hir >= compact_count)
        return INVALID;

    HirCore call_core = compact_hir_core[call_hir];
    uint callee_hir = compact_hir_payload[call_hir].a;
    if (call_core.kind != HIR_CALL_EXPR || callee_hir == INVALID || callee_hir >= compact_count)
        return INVALID;

    HirCore callee_core = compact_hir_core[callee_hir];
    if (callee_core.kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_hir].c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    return valid_token(callee_core.token_start) ? callee_core.token_start : INVALID;
}

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

uint generic_owner_token(uint decl_node)
{
    if (!valid_node(decl_node))
        return INVALID;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (decl_node >= count)
        return canonical_function_token(decl_node);
    return hir_generic_owner_token(compact_hir_core[decl_node], compact_hir_payload[decl_node],
        gParams.n_tokens);
}

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_token[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
}

uint generic_param_row_for_name(uint decl_node, uint name_token, uint kind)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint owner_token = generic_owner_token(decl_node);
    if (!valid_token(owner_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    uint row = generic_param_lookup_find(
        owner_token, name_id, count, gParams.n_tokens,
        generic_param_owner_token, generic_param_name_id,
        generic_param_lookup_state);
    return generic_param_key_matches(row, owner_token, name_id, kind) ? row : INVALID;
}

uint generic_param_slot_for_name(uint decl_node, uint name_token)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint row = generic_param_row_for_name(decl_node, name_token, GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
        return INVALID;

    uint param_token = generic_param_token[row];
    return valid_token(param_token) ? type_generic_param_slot_by_token[param_token] : INVALID;
}

uint2 impl_subject_reference(uint impl_node)
{
    return predicate_type_reference(valid_node(impl_node)
        ? compact_hir_semantic_facts[impl_node].method_impl_receiver_type : INVALID);
}

bool impl_row_has_supported_exact_key(uint impl_node)
{
    // The source exact-key index contains only concrete implementations.
    // Generic head selection and coherence belong to whole-program admission.
    return valid_node(impl_node) && compact_generic_param_ranges[impl_node].count == 0u &&
        predicate_owner_node[impl_node] == impl_node &&
        predicate_status[impl_node] == PREDICATE_STATUS_OK &&
        predicate_bound_reference[impl_node] != INVALID && predicate_bound_arg_count[impl_node] <= 32u;
}

uint impl_index_match_count(uint bound_reference, uint2 subject, uint root, uint context,
    uint arg_count, uint hash, out uint first_match)
{
    first_match = INVALID;
    uint count = active_sorted_predicate_count();
    if (count == 0u) return 0u;
    uint bucket = predicate_impl_lookup_bucket(bound_reference, arg_count, hash, count);
    uint link = predicate_impl_lookup_head[bucket];
    uint matches = 0u;
    uint first_token = INVALID;
    for (uint visited = 0u; visited < count && link != 0u; visited++)
    {
        uint impl_node = link - 1u;
        if (!valid_node(impl_node)) return INVALID;
        if (impl_row_has_supported_exact_key(impl_node) &&
            trait_references_equal(predicate_bound_reference[impl_node], bound_reference) &&
            predicate_bound_arg_count[impl_node] == arg_count &&
            predicate_keys_equal<PredicateTypeGraph>(
                impl_subject_reference(impl_node), predicate_trait_impl_trait_type_node[impl_node], INVALID,
                subject, root, context, arg_count))
        {
            matches++;
            uint token = compact_hir_core[impl_node].token_start;
            if (first_match == INVALID || token < first_token ||
                (token == first_token && impl_node < first_match))
            { first_match = impl_node; first_token = token; }
        }
        link = predicate_impl_lookup_next[impl_node];
    }
    return link == 0u ? matches : INVALID;
}

void validate_unique_impl_key(uint impl_node)
{
    if (!impl_row_has_supported_exact_key(impl_node)) return;
    uint count = predicate_bound_arg_count[impl_node];
    uint root = predicate_trait_impl_trait_type_node[impl_node];
    uint2 subject = impl_subject_reference(impl_node);
    uint hash;
    if (!predicate_key_hash<PredicateTypeGraph>(subject, root, count, INVALID, hash))
    {
        record_error(compact_hir_core[impl_node].token_start,
            ERR_INVALID_TRAIT_IMPLEMENTATION, PREDICATE_STATUS_INVALID_IMPL_ARG);
        return;
    }
    uint first_match;
    uint matches = impl_index_match_count(predicate_bound_reference[impl_node], subject,
        root, INVALID, count, hash, first_match);
    if (matches == 0u || matches == INVALID || (matches > 1u && first_match != impl_node))
        record_error(compact_hir_core[impl_node].token_start,
            ERR_INVALID_TRAIT_IMPLEMENTATION, PREDICATE_STATUS_OVERLAPPING_IMPL);
}

void validate_predicate_fail_closed_status(uint node)
{
    uint status_value = predicate_status[node];
    uint kind = compact_hir_semantic_facts[node].semantic_kind;
    bool trait_contract_node =
        kind == HIR_SEMANTIC_IMPL_TRAIT ||
        kind == HIR_SEMANTIC_IMPL_INHERENT ||
        kind == HIR_SEMANTIC_IMPL_FUNCTION ||
        kind == HIR_SEMANTIC_TRAIT_METHOD ||
        kind == HIR_SEMANTIC_PUBLIC_TRAIT_METHOD;

    bool trait_bound_status = !trait_contract_node && (
        status_value == PREDICATE_STATUS_UNSUPPORTED_CONST_TRAIT ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        status_value == PREDICATE_STATUS_INVALID_ARG ||
        (status_value == PREDICATE_STATUS_INVALID_SUBJECT ||
          status_value == PREDICATE_STATUS_BOUND_NOT_TRAIT ||
          status_value == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
          status_value == PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND));
    if (trait_bound_status)
    {
        uint token_i = compact_hir_core[node].token_start;
        if (status_value == PREDICATE_STATUS_INVALID_SUBJECT &&
            valid_token(predicate_subject_token[node]))
            token_i = predicate_subject_token[node];
        if ((status_value == PREDICATE_STATUS_INVALID_ARG ||
             status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
             status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION) &&
            (valid_token(predicate_bound_first_arg_token[node]) ||
             valid_token(predicate_bound_second_arg_token[node])))
            token_i = valid_token(predicate_bound_second_arg_token[node])
                ? predicate_bound_second_arg_token[node]
                : predicate_bound_first_arg_token[node];
        if (status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE &&
            token_i == compact_hir_core[node].token_start)
        {
            uint fallback_token = first_named_bound_arg_token_after_bound(node);
            if (valid_token(fallback_token))
                token_i = fallback_token;
        }
        record_error(
            valid_token(token_i) ? token_i : 0u,
            ERR_TRAIT_BOUND_UNSATISFIED,
            status_value);
        return;
    }

    if (!trait_contract_node)
        return;

    bool trait_contract_status =
        status_value == PREDICATE_STATUS_UNSUPPORTED_CONST_TRAIT ||
        status_value == PREDICATE_STATUS_BOUND_NOT_TRAIT ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        status_value == PREDICATE_STATUS_MISSING_METHOD ||
        status_value == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
        status_value == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
        status_value == PREDICATE_STATUS_BOUND_ARITY_MISMATCH ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_TARGET_SHAPE ||
        status_value == PREDICATE_STATUS_INVALID_IMPL_ARG ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
        status_value == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD ||
        status_value == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
        status_value == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
        status_value == PREDICATE_STATUS_IMPL_VISIBILITY_MISMATCH ||
        status_value == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG ||
        status_value == PREDICATE_STATUS_UNCONSTRAINED_IMPL_PARAMETER ||
        status_value == PREDICATE_STATUS_IMPL_HEAD_WORK_LIMIT;
    if (!trait_contract_status)
        return;

    bool impl_head_status =
        status_value == PREDICATE_STATUS_UNCONSTRAINED_IMPL_PARAMETER ||
        status_value == PREDICATE_STATUS_IMPL_HEAD_WORK_LIMIT;
    uint token_i = impl_head_status ? compact_hir_core[node].token_start :
        predicate_bound_first_arg_token[node];
    bool trait_impl_arg_status =
        status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        status_value == PREDICATE_STATUS_INVALID_IMPL_ARG ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
    if (trait_impl_arg_status && valid_token(predicate_bound_second_arg_token[node]))
        token_i = predicate_bound_second_arg_token[node];
    if (!valid_token(token_i))
        token_i = compact_hir_core[node].token_start;
    record_error(
        valid_token(token_i) ? token_i : 0u,
        ERR_INVALID_TRAIT_IMPLEMENTATION,
        status_value);
}

// An enclosing generic contract proves the same symbolic obligation. Keep
// declaration identity and the entire ordered argument graph in that proof;
// neither matching names nor matching slot numbers implies a bound.
bool caller_contract_satisfies(uint call_node, uint required, uint2 subject, uint context)
{
    // A method can own predicates without owning a generic header. Start at
    // its actual callable, then visit enclosing generic scopes explicitly.
    uint owner = valid_node(call_node) ? compact_hir_nearest_fn[call_node] : INVALID;
    uint count = active_sorted_predicate_count();
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (count == 0u) return false;
    for (uint depth = 0u; depth < hir_count && valid_node(owner); depth++)
    {
        uint owner_token = canonical_function_token(owner);
        if (!valid_token(owner_token)) return false;
        uint link = predicate_owner_lookup_head[predicate_owner_lookup_bucket(owner_token, count)];
        for (uint visited = 0u; visited < count && link != 0u; visited++)
        {
            uint offered = link - 1u;
            if (!valid_node(offered)) return false;
            if (predicate_owner_node[offered] == owner && predicate_status[offered] == PREDICATE_STATUS_OK &&
                trait_references_equal(predicate_bound_reference[offered], predicate_bound_reference[required]) &&
                predicate_bound_arg_count[offered] == predicate_bound_arg_count[required])
            {
                uint row = lexical_parameter_row(offered, predicate_subject_token[offered], GENERIC_PARAM_KIND_TYPE);
                if (row != INVALID && predicate_keys_equal<PredicateTypeGraph>(
                    uint2(TYPE_REF_GENERIC_PARAM, generic_param_token[row]), offered, INVALID,
                    subject, required, context, predicate_bound_arg_count[required])) return true;
            }
            link = predicate_owner_lookup_next[offered];
        }
        if (link != 0u) return false;
        uint enclosing = lexical_parameter_parent(owner);
        if (enclosing == owner) return false;
        owner = enclosing;
    }
    return false;
}

// The subject of accepted predicate `pred` in its owner's scope: the type
// parameter it names, as (TYPE_REF_GENERIC_PARAM, declaration token), or the
// scalar type it names (predicates/scalar_subject.slang). (0, INVALID) when it
// names neither.
uint2 predicate_subject_ref(uint pred)
{
    uint token = predicate_subject_token[pred];
    uint row = lexical_parameter_row(pred, token, GENERIC_PARAM_KIND_TYPE);
    if (row != INVALID) return uint2(TYPE_REF_GENERIC_PARAM, generic_param_token[row]);
    uint code = predicate_scalar_subject_code(token, name_id_by_token, language_type_code_by_name_id);
    return code != INVALID ? uint2(TYPE_REF_SCALAR, code) : uint2(0u, INVALID);
}

void validate_trait_obligation_for_call(uint pred, uint fn_node, uint node)
{
    uint callee = call_callee_token(node);
    if (!valid_token(callee) || !valid_node(fn_node) ||
        canonical_function_token(fn_node) != call_fn_index[callee]) return;
    uint2 subject = predicate_subject_ref(pred);
    if (subject.x == 0u)
    {
        record_error(callee, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_SUBJECT);
        return;
    }
    uint count = predicate_bound_arg_count[pred];
    uint context = 0x80000000u | callee;
    if (caller_contract_satisfies(node, pred, subject, context)) return;
    uint hash;
    if (!predicate_key_hash<PredicateTypeGraph>(subject, pred, count, context, hash))
    {
        record_error(callee, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_ARG);
        return;
    }
    // Original admission and authorized replay both retain every generic call
    // for whole-program selection. Replay reparses ordinary siblings as well:
    // their calls must preserve the admitted original facts, while selected-body
    // calls receive fresh proofs. Omitted templates recover originals only after
    // the native emission gate proves they emitted no bodies or calls.
    // All objects remain private until that gate and program checking succeed.
    // Keep definition, owner, environment and full key validation above. Intrinsic
    // calls have no retained callable row, so their bounds must stay strict.
    uint replay_owner = gParams.authorized_replay_callable;
    bool authorized_replay = gParams.trait_obligation_mode == 2u &&
        valid_node(replay_owner) && compact_hir_core[replay_owner].kind == 3u;
    if ((gParams.trait_obligation_mode == 1u || authorized_replay) &&
        call_intrinsic_tag[callee] == 0u) return;
    uint first_match;
    uint matches = impl_index_match_count(predicate_bound_reference[pred], subject,
        pred, context, count, hash, first_match);
    if (matches != 1u)
        record_error(callee,
            matches == 0u ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_TRAIT_BOUND_AMBIGUOUS,
            matches == 0u ? PREDICATE_STATUS_UNSATISFIED_BOUND : PREDICATE_STATUS_AMBIGUOUS_BOUND);
}

// Resolve the accepted local callable before walking its lexical contract.
// Dependency calls have their own interface obligation path; declaration
// indices or call tokens must never alias a source callable owner.
uint call_contract_owner(uint callee)
{
    if (!valid_token(callee) || call_dependency_library_id[callee] != INVALID)
        return INVALID;
    uint target = call_fn_index[callee];
    if (!valid_token(target)) return INVALID;
    uint owner = fn_hir_by_decl_token[target];
    return valid_node(owner) && compact_hir_core[owner].kind == 3u &&
        canonical_function_token(owner) == target ? owner : INVALID;
}

bool callable_contract_parent(uint owner, out uint parent)
{
    parent = INVALID;
    if (!valid_node(owner)) return false;
    // An impl is the outermost callable contract scope. A free function has
    // no method row. Use the checked method relation even for headerless
    // methods and nongeneric impls; the nearest-generic map skips both.
    if (compact_hir_core[owner].kind == 35u) return true;
    if (compact_hir_core[owner].kind != 3u) return false;
    uint row = compact_method_row_for_hir(compact_method_cores,
        min(compact_method_count[0u], active_hir_node_count()), owner);
    if (row == INVALID) return true;
    parent = compact_method_cores[row].impl_node;
    // Required trait members have no implementation parent.
    if (parent == INVALID) return true;
    return valid_node(parent) && parent != owner && compact_hir_core[parent].kind == 35u;
}

// Count and selection share the same complete owner walk and exact HIR join.
// The bucket token is only an index: predicate ownership is never inferred
// from a coincident token, name, or generic slot. Keep the selected predicate
// root unchanged so inherited operands use the original call environment.
uint callable_contract_predicate(uint function, uint ordinal,
    out uint total, out bool valid_index)
{
    total = 0u;
    valid_index = false;
    uint selected = INVALID;
    uint owner = function;
    uint count = active_sorted_predicate_count();
    for (uint depth = 0u; depth < active_hir_node_count() && valid_node(owner); depth++)
    {
        uint owner_token = canonical_function_token(owner);
        if (!valid_token(owner_token)) return INVALID;
        uint link = count == 0u ? 0u :
            predicate_owner_lookup_head[predicate_owner_lookup_bucket(owner_token, count)];
        for (uint visited = 0u; visited < count && link != 0u; visited++)
        {
            uint pred = link - 1u;
            if (!valid_node(pred)) return INVALID;
            if (predicate_owner_node[pred] == owner && pred != owner &&
                predicate_status[pred] == PREDICATE_STATUS_OK)
            {
                if (total == ordinal) selected = pred;
                total++;
                if (total > PREDICATE_OBLIGATION_WINDOW)
                {
                    // The count pass reports the existing explicit work limit.
                    valid_index = true;
                    return INVALID;
                }
            }
            link = predicate_owner_lookup_next[pred];
        }
        if (link != 0u) return INVALID;
        uint parent;
        if (!callable_contract_parent(owner, parent)) return INVALID;
        owner = parent;
    }
    valid_index = owner == INVALID;
    return valid_index ? selected : INVALID;
}

#if defined(LANIUS_OBLIGATION_COUNT_PASS)
void count_call_predicate_obligations(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;

    uint function = call_contract_owner(callee_token);
    if (!valid_node(function)) return;

    bool valid_owner_index;
    uint obligation_count;
    callable_contract_predicate(function, INVALID, obligation_count, valid_owner_index);
    if (!valid_owner_index)
    {
        record_error(
            callee_token,
            ERR_TRAIT_BOUND_AMBIGUOUS,
            PREDICATE_STATUS_AMBIGUOUS_BOUND);
        return;
    }

    if (obligation_count > PREDICATE_OBLIGATION_WINDOW)
    {
        record_error(
            callee_token,
            ERR_TRAIT_BOUND_UNSATISFIED,
            PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW);
        return;
    }

    predicate_obligation_count_by_call[call_node] = obligation_count;
}
#endif

#if defined(LANIUS_OBLIGATION_VALIDATE_PASS)
public struct ObligationPairLookupKey
{
    uint pair_row;
}

uint call_obligation_end(uint call_node)
{
    if (!valid_node(call_node))
        return 0u;

    uint prefix = predicate_obligation_prefix_by_call[call_node];
    uint count = predicate_obligation_count_by_call[call_node];
    return prefix > 0xffffffffu - count ? 0xffffffffu : prefix + count;
}

public struct ObligationPairEndCompare : IRowQueryCompare<ObligationPairLookupKey>
{
    public static int compare(uint row, ObligationPairLookupKey key)
    {
        if (row >= active_hir_node_count())
            return 1;
        return fixed_u32_lane_compare(call_obligation_end(row), key.pair_row);
    }
}

uint call_node_for_obligation_pair(uint pair_row)
{
    ObligationPairLookupKey key;
    key.pair_row = pair_row;
    uint row = upper_bound_query<ObligationPairLookupKey, ObligationPairEndCompare>(
        active_hir_node_count(),
        key);
    return valid_node(row) ? row : INVALID;
}

void validate_call_predicate_obligation_pair(uint pair_row)
{
    if (pair_row >= predicate_obligation_pair_total[0u])
        return;

    uint call_node = call_node_for_obligation_pair(pair_row);
    if (!valid_node(call_node))
        return;

    uint count = predicate_obligation_count_by_call[call_node];
    if (count == 0u)
        return;

    uint prefix = predicate_obligation_prefix_by_call[call_node];
    if (pair_row < prefix)
        return;

    uint offset = pair_row - prefix;
    if (offset >= count)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;

    uint function = call_contract_owner(callee_token);
    bool valid_owner_index;
    uint contract_count;
    uint pred = callable_contract_predicate(function, offset, contract_count, valid_owner_index);
    if (!valid_owner_index || contract_count != count || !valid_node(pred))
    {
        record_error(
            callee_token,
            ERR_TRAIT_BOUND_AMBIGUOUS,
            PREDICATE_STATUS_AMBIGUOUS_BOUND);
        return;
    }
    if (predicate_status[pred] != PREDICATE_STATUS_OK)
        return;

    // Enumeration established the exact method/impl owner relation. Validate
    // the actual callee while resolving subject and operand roots at pred.
    validate_trait_obligation_for_call(pred, function, call_node);
}
#endif
