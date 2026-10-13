// Validate trait obligations using complete ordered type graphs and accepted
// call environments. Concrete impl keys share the same graph equality/hash
// contract as ordinary generic calls; up to 32 trait arguments are supported.

import hir_records;
import type_checker.type.instances.generic_param_lookup;
import fixed.key;
import hir_expr_semantics;
import range_query;
import status;
import type_checker.predicates.owner_lookup;
import type_checker.predicates.impl_lookup;
import type_checker.calls.checked_call_type_graph;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> generic_decl_owner_by_node_a;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_lookup_state;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_decl_id;
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

static const uint INVALID = 0xffffffffu;

static const uint ERR_TRAIT_BOUND_UNSATISFIED = 13u;
static const uint ERR_TRAIT_BOUND_AMBIGUOUS = 14u;
static const uint ERR_INVALID_TRAIT_IMPLEMENTATION = 17u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;



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
    uint token = compact_hir_payload[node].b;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
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
    uint name_token = compact_hir_payload[decl_node].b;
    return valid_token(name_token) ? name_token : canonical_function_token(decl_node);
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
    return valid_node(impl_node) && predicate_owner_node[impl_node] == impl_node &&
        predicate_status[impl_node] == PREDICATE_STATUS_OK &&
        predicate_bound_decl_id[impl_node] != INVALID && predicate_bound_arg_count[impl_node] <= 32u;
}

uint impl_index_match_count(uint bound_decl_id, uint2 subject, uint root, uint context,
    uint arg_count, uint hash, out uint first_match)
{
    first_match = INVALID;
    uint count = active_sorted_predicate_count();
    if (count == 0u) return 0u;
    uint bucket = predicate_impl_lookup_bucket(bound_decl_id, arg_count, hash, count);
    uint link = predicate_impl_lookup_head[bucket];
    uint matches = 0u;
    uint first_token = INVALID;
    for (uint visited = 0u; visited < count && link != 0u; visited++)
    {
        uint impl_node = link - 1u;
        if (!valid_node(impl_node)) return INVALID;
        if (impl_row_has_supported_exact_key(impl_node) &&
            predicate_bound_decl_id[impl_node] == bound_decl_id &&
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
    uint matches = impl_index_match_count(predicate_bound_decl_id[impl_node], subject,
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
        status_value == PREDICATE_STATUS_UNSUPPORTED_IMPL_GENERIC_ARG;
    if (!trait_contract_status)
        return;

    uint token_i = predicate_bound_first_arg_token[node];
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
    uint owner = valid_node(call_node) ? generic_decl_owner_by_node_a[call_node] : INVALID;
    uint owner_token = valid_node(owner) ? canonical_function_token(owner) : INVALID;
    uint count = active_sorted_predicate_count();
    if (!valid_token(owner_token) || count == 0u) return false;
    uint link = predicate_owner_lookup_head[predicate_owner_lookup_bucket(owner_token, count)];
    for (uint visited = 0u; visited < count && link != 0u; visited++)
    {
        uint offered = link - 1u;
        if (!valid_node(offered)) return false;
        if (predicate_owner_node[offered] == owner && predicate_status[offered] == PREDICATE_STATUS_OK &&
            predicate_bound_decl_id[offered] == predicate_bound_decl_id[required] &&
            predicate_bound_arg_count[offered] == predicate_bound_arg_count[required])
        {
            uint row = generic_param_row_for_name(owner, predicate_subject_token[offered], GENERIC_PARAM_KIND_TYPE);
            if (row != INVALID && predicate_keys_equal<PredicateTypeGraph>(
                uint2(TYPE_REF_GENERIC_PARAM, generic_param_token[row]), offered, INVALID,
                subject, required, context, predicate_bound_arg_count[required])) return true;
        }
        link = predicate_owner_lookup_next[offered];
    }
    return false;
}

void validate_trait_obligation_for_call(uint pred, uint fn_node, uint node)
{
    uint callee = call_callee_token(node);
    if (!valid_token(callee) || !valid_node(fn_node) ||
        canonical_function_token(fn_node) != call_fn_index[callee]) return;
    uint row = generic_param_row_for_name(fn_node, predicate_subject_token[pred], GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
    {
        record_error(callee, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_SUBJECT);
        return;
    }
    uint2 subject = uint2(TYPE_REF_GENERIC_PARAM, generic_param_token[row]);
    uint count = predicate_bound_arg_count[pred];
    uint context = 0x80000000u | callee;
    if (caller_contract_satisfies(node, pred, subject, context)) return;
    uint hash;
    if (!predicate_key_hash<PredicateTypeGraph>(subject, pred, count, context, hash))
    {
        record_error(callee, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_ARG);
        return;
    }
    uint first_match;
    uint matches = impl_index_match_count(predicate_bound_decl_id[pred], subject,
        pred, context, count, hash, first_match);
    if (matches != 1u)
        record_error(callee,
            matches == 0u ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_TRAIT_BOUND_AMBIGUOUS,
            matches == 0u ? PREDICATE_STATUS_UNSATISFIED_BOUND : PREDICATE_STATUS_AMBIGUOUS_BOUND);
}

bool owner_predicate_matches(uint pred, uint owner_token)
{
    if (!valid_node(pred) || predicate_status[pred] != PREDICATE_STATUS_OK)
        return false;

    uint owner = predicate_owner_node[pred];
    return valid_node(owner) &&
           owner != pred &&
           canonical_function_token(owner) == owner_token;
}

uint owner_predicate_count(uint owner_token, out bool valid_index)
{
    valid_index = true;
    uint predicate_count = active_sorted_predicate_count();
    if (!valid_token(owner_token) || predicate_count == 0u)
        return 0u;

    uint bucket = predicate_owner_lookup_bucket(owner_token, predicate_count);
    uint link = predicate_owner_lookup_head[bucket];
    uint visited = 0u;
    uint matches = 0u;
    while (link != 0u && visited < predicate_count)
    {
        uint pred = link - 1u;
        if (!valid_node(pred))
        {
            valid_index = false;
            return 0u;
        }
        if (owner_predicate_matches(pred, owner_token))
            matches += 1u;
        link = predicate_owner_lookup_next[pred];
        visited += 1u;
    }

    valid_index = link == 0u;
    return valid_index ? matches : 0u;
}

uint owner_predicate_at(uint owner_token, uint offset, out bool valid_index)
{
    valid_index = true;
    uint predicate_count = active_sorted_predicate_count();
    if (!valid_token(owner_token) || predicate_count == 0u)
        return INVALID;

    uint bucket = predicate_owner_lookup_bucket(owner_token, predicate_count);
    uint link = predicate_owner_lookup_head[bucket];
    uint visited = 0u;
    uint match_index = 0u;
    while (link != 0u && visited < predicate_count)
    {
        uint pred = link - 1u;
        if (!valid_node(pred))
        {
            valid_index = false;
            return INVALID;
        }
        if (owner_predicate_matches(pred, owner_token))
        {
            if (match_index == offset)
                return pred;
            match_index += 1u;
        }
        link = predicate_owner_lookup_next[pred];
        visited += 1u;
    }

    valid_index = link == 0u;
    return INVALID;
}

#if defined(LANIUS_OBLIGATION_COUNT_PASS)
void count_call_predicate_obligations(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token))
        return;

    bool valid_owner_index;
    uint obligation_count = owner_predicate_count(fn_token, valid_owner_index);
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

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token))
        return;

    bool valid_owner_index;
    uint pred = owner_predicate_at(fn_token, offset, valid_owner_index);
    if (!valid_owner_index || !valid_node(pred))
    {
        record_error(
            callee_token,
            ERR_TRAIT_BOUND_AMBIGUOUS,
            PREDICATE_STATUS_AMBIGUOUS_BOUND);
        return;
    }
    if (predicate_status[pred] != PREDICATE_STATUS_OK)
        return;

    uint fn_node = predicate_owner_node[pred];
    if (!valid_node(fn_node))
        return;

    validate_trait_obligation_for_call(pred, fn_node, call_node);
}
#endif
