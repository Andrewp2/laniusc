// Validates first-order trait obligations at direct generic call sites.
//
// This pass consumes predicate rows plus HIR call/parameter/type attribution
// records. It intentionally stays bounded: direct calls only, concrete impl
// rows only, and trait bounds with at most two type arguments.

import hir_records;
import type_checker.type.instances.generic_param_lookup;
import fixed.key;
import hir_expr_semantics;
import range_query;
import status;
import type_checker.predicates.owner_lookup;
import type_checker.predicates.impl_lookup;
import type_checker.calls.claim_lookup;

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
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
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
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;

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

static const uint PREDICATE_OBLIGATION_WINDOW = 32u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

uint compact_node_for_raw(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return node < count ? node : INVALID;
}

uint compact_expr_for_raw(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint result = compact_hir_semantic_facts[node].expr_result_root;
    return compact_node_for_raw(valid_node(result) ? result : node);
}

uint compact_expr_form(uint node)
{
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return node < count ? compact_hir_payload[node].a : 0u;
}

uint compact_expr_value_token(uint node)
{
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (node >= count)
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

uint visible_type_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    uint ty = visible_type[token_i];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token_i];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token_i];
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

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint expr = compact_expr_for_raw(node);
    uint lit = valid_node(expr)
        ? hir_scalar_type_for_hir(compact_hir_core[expr].kind, compact_expr_form(expr))
        : TY_UNKNOWN;
    if (lit != TY_UNKNOWN)
        return lit;

    uint token_i = compact_hir_core[node].token_start;
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    if (compact_hir_core[node].kind == HIR_NAME_EXPR)
        return visible_type_for_token(token_i);

    if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[node].c;
        return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
    }

    if (compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR)
    {
        uint head_node = compact_hir_semantic_facts[node].struct_lit_head;
        if (!valid_node(head_node))
            return TY_UNKNOWN;
        return visible_type_for_token(compact_hir_core[head_node].token_start);
    }

    if (compact_hir_core[node].kind == HIR_INDEX_EXPR ||
        compact_hir_core[node].kind == HIR_MATCH_EXPR)
        return call_return_type[token_i];

    if (compact_hir_core[node].kind == HIR_CALL_EXPR)
    {
        uint callee_token = call_callee_token(node);
        if (!valid_token(callee_token))
            callee_token = compact_hir_core[node].token_start;
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

uint direct_compact_node_type(uint node)
{
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (node >= count)
        return TY_UNKNOWN;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint literal = hir_scalar_type_for_hir(core.kind, payload.a);
    if (literal != TY_UNKNOWN)
        return literal;
    if (core.kind == HIR_NAME_EXPR)
        return visible_type_for_token(compact_expr_value_token(node));
    if (core.kind == HIR_MEMBER_EXPR)
        return visible_type_for_token(payload.c);
    if (core.kind == HIR_INDEX_EXPR || core.kind == HIR_MATCH_EXPR)
        return valid_token(core.token_start) ? call_return_type[core.token_start] : TY_UNKNOWN;
    if (core.kind != HIR_CALL_EXPR || payload.a >= count)
        return TY_UNKNOWN;

    uint token = call_callee_token(node);
    return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;
}

uint direct_expr_record_type(uint node)
{
    uint expr = compact_expr_for_raw(node);
    uint compact_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (expr >= compact_count)
        return TY_UNKNOWN;

    uint direct_ty = direct_compact_node_type(expr);
    if (direct_ty != TY_UNKNOWN)
        return direct_ty;

    uint form = compact_expr_form(expr);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(compact_expr_value_token(expr));

    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return TY_BOOL;

    if (form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_DIV)
    {
        HirPayload payload = compact_hir_payload[expr];
        uint left_ty = direct_compact_node_type(payload.b);
        uint right_ty = direct_compact_node_type(payload.c);
        return left_ty == TY_FLOAT || right_ty == TY_FLOAT ? TY_FLOAT : TY_INT;
    }

    if (form == HIR_EXPR_MOD ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

uint first_value_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint result = compact_hir_semantic_facts[root].expr_result_root;
    if (!valid_node(result))
        result = root;
    uint expr = compact_expr_for_raw(result);
    uint compact_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (expr >= compact_count)
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(result);
    if (record_ty != TY_UNKNOWN)
    {
        uint token_i = valid_token(compact_expr_value_token(expr))
            ? compact_expr_value_token(expr)
            : compact_hir_core[result].token_start;
        value_token = valid_token(token_i) ? token_i : INVALID;
        return record_ty;
    }

    uint result_ty = direct_node_type(result);
    if (result_ty != TY_UNKNOWN)
    {
        uint token_i = compact_hir_core[result].kind == HIR_MEMBER_EXPR
            ? compact_hir_payload[result].c
            : compact_hir_core[result].token_start;
        value_token = valid_token(token_i) ? token_i : INVALID;
        return result_ty;
    }

    return TY_UNKNOWN;
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint type_code_for_type_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = type_code_for_ref(type_expr_ref_tag[token], type_expr_ref_payload[token]);
    if (ty != TY_UNKNOWN)
        return ty;
    return visible_type_for_token(token);
}

bool exact_impl_key_type_supported(uint ty)
{
    return ty != TY_UNKNOWN && ty < TY_GENERIC_BASE;
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

uint call_arg_node_for_ordinal(uint call_node, uint ordinal)
{
    if (!valid_node(call_node))
        return INVALID;

    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    return row < active_hir_node_count() ? call_arg_row_node[row] : INVALID;
}

uint call_arg_count_for_callee(uint callee_token, uint call_node)
{
    if (!valid_token(callee_token))
        return 0u;
    uint record_count = call_arg_record[callee_token].w;
    if (!valid_node(call_node))
        return record_count;
    return max(record_count, call_arg_row_count[call_node]);
}

uint generic_claim_capacity()
{
    uint base = max(gParams.n_tokens, gParams.n_hir_nodes);
    return base > 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER
        ? 0xffffffffu
        : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
}

uint concrete_claim_key(uint row)
{
    uint ty = call_generic_claim_type[row];
    return call_generic_claim_callee[row] != INVALID &&
           call_generic_claim_slot[row] != INVALID &&
           ty != TY_UNKNOWN && ty < TY_GENERIC_BASE
        ? 1u
        : 0u;
}

uint generic_claim_type_for_slot(uint callee_token, uint slot)
{
    if (!valid_token(callee_token) || slot == INVALID)
        return TY_UNKNOWN;

    uint count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    uint bucket = call_claim_lookup_bucket(callee_token, slot, count);
    uint link = call_generic_claim_lookup_head[bucket];
    uint result = TY_UNKNOWN;
    uint best_row = INVALID;
    for (uint step = 0u; step < count && link != 0u; step += 1u)
    {
        uint row = link - 1u;
        if (row >= count)
            break;
        if (row < best_row && concrete_claim_key(row) != 0u &&
            call_generic_claim_callee[row] == callee_token &&
            call_generic_claim_slot[row] == slot)
        {
            best_row = row;
            result = call_generic_claim_type[row];
        }
        link = call_generic_claim_lookup_next[row];
    }
    return result;
}

bool param_row_matches(uint row, uint fn_token, uint ordinal)
{
    return row < call_param_row_count_out[0u] &&
           call_param_row_fn_token[row] == fn_token &&
           call_param_row_ordinal[row] == ordinal;
}

uint param_ref_row_for_ordinal(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token])
        return INVALID;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    if (start == INVALID || count == 0u || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    if (row < start || row >= call_param_row_count_out[0u])
        return INVALID;

    return param_row_matches(row, fn_token, ordinal) ? row : INVALID;
}

bool param_ref_uses_generic_slot(uint fn_node, uint fn_token, uint ordinal, uint slot)
{
    if (!valid_token(fn_token) || slot == INVALID)
        return false;

    uint ref_i = param_ref_row_for_ordinal(fn_token, ordinal);
    if (ref_i == INVALID)
        return false;

    uint tag = call_param_row_ref_tag[ref_i];
    uint payload = call_param_row_ref_payload[ref_i];
    if (tag != TYPE_REF_GENERIC_PARAM || !valid_token(payload))
        return false;

    uint payload_slot = type_generic_param_slot_by_token[payload];
    if (payload_slot == INVALID)
        payload_slot = generic_param_slot_for_name(fn_node, payload);
    return payload_slot == slot;
}

uint actual_type_for_generic_slot_with_detail(
    uint call_node,
    uint fn_node,
    uint slot,
    out uint failure_detail)
{
    failure_detail = PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW;
    if (!valid_node(call_node) || !valid_node(fn_node) || slot == INVALID)
        return TY_UNKNOWN;

    uint fn_token = canonical_function_token(fn_node);
    if (!valid_token(fn_token))
        return TY_UNKNOWN;

    uint count = call_param_count[fn_token];
    if (count == 0u)
    {
        failure_detail = PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW;
        return TY_UNKNOWN;
    }

    uint callee_token = call_callee_token(call_node);
    uint claimed = generic_claim_type_for_slot(callee_token, slot);
    if (claimed != TY_UNKNOWN)
    {
        failure_detail = PREDICATE_STATUS_OK;
        return claimed;
    }

    if (count > PARAM_CACHE_STRIDE)
    {
        if (valid_token(callee_token) && slot < PARAM_CACHE_STRIDE)
        {
            uint inferred = call_generic_slot_type[callee_token * PARAM_CACHE_STRIDE + slot];
            if (inferred != INVALID)
            {
                failure_detail = PREDICATE_STATUS_OK;
                return inferred;
            }
        }
        failure_detail = PREDICATE_STATUS_INVALID_SUBJECT;
        return TY_UNKNOWN;
    }

    uint found = TY_UNKNOWN;
    bool participates = false;
    for (uint ordinal = 0u; ordinal < PARAM_CACHE_STRIDE; ordinal += 1u)
    {
        if (ordinal >= count)
            break;
        if (!param_ref_uses_generic_slot(fn_node, fn_token, ordinal, slot))
            continue;

        participates = true;
        uint arg_node = call_arg_node_for_ordinal(call_node, ordinal);
        if (!valid_node(arg_node))
        {
            failure_detail = PREDICATE_STATUS_INVALID_ARG;
            return TY_UNKNOWN;
        }

        uint value_token = INVALID;
        uint actual = first_value_type_from_node(arg_node, value_token);
        if (actual == TY_UNKNOWN)
        {
            failure_detail = PREDICATE_STATUS_INVALID_ARG;
            return TY_UNKNOWN;
        }
        if (found == TY_UNKNOWN)
            found = actual;
        else if (found != actual)
        {
            failure_detail = PREDICATE_STATUS_INVALID_ARG;
            return TY_UNKNOWN;
        }
    }
    if (found != TY_UNKNOWN)
        failure_detail = PREDICATE_STATUS_OK;
    else if (!participates)
        failure_detail = PREDICATE_STATUS_INVALID_SUBJECT;
    return found;
}

uint actual_type_for_generic_slot(uint call_node, uint fn_node, uint slot)
{
    uint failure_detail = PREDICATE_STATUS_OK;
    return actual_type_for_generic_slot_with_detail(call_node, fn_node, slot, failure_detail);
}

uint predicate_bound_arg_token(uint pred_node, uint ordinal)
{
    if (ordinal == 0u)
        return predicate_bound_first_arg_token[pred_node];
    if (ordinal == 1u)
        return predicate_bound_second_arg_token[pred_node];
    return INVALID;
}

bool predicate_arg_is_encoded_type(uint arg)
{
    return arg != INVALID && (arg & PREDICATE_ARG_TYPE_CODE_BIT) != 0u;
}

uint predicate_arg_type_code(uint arg)
{
    if (predicate_arg_is_encoded_type(arg))
        return arg & ~PREDICATE_ARG_TYPE_CODE_BIT;
    return type_code_for_type_token(arg);
}

uint predicate_type_code(uint value)
{
    return predicate_arg_type_code(value);
}

uint predicate_arg_concrete_type(uint pred_node, uint fn_node, uint call_node, uint ordinal)
{
    uint token = predicate_bound_arg_token(pred_node, ordinal);
    if (predicate_arg_is_encoded_type(token))
        return predicate_arg_type_code(token);

    if (!valid_token(token))
        return TY_UNKNOWN;

    uint slot = generic_param_slot_for_name(fn_node, token);
    if (slot != INVALID)
        return actual_type_for_generic_slot(call_node, fn_node, slot);

    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint payload_slot = type_generic_param_slot_by_token[payload];
        if (payload_slot == INVALID)
            payload_slot = generic_param_slot_for_name(fn_node, payload);
        return actual_type_for_generic_slot(call_node, fn_node, payload_slot);
    }
    return type_code_for_ref(tag, payload);
}

bool impl_row_has_supported_exact_key(uint impl_node)
{
    if (!valid_node(impl_node) ||
        predicate_owner_node[impl_node] != impl_node ||
        predicate_status[impl_node] != PREDICATE_STATUS_OK)
        return false;

    if (!valid_node(predicate_bound_decl_id[impl_node]))
        return false;

    uint subject_ty = predicate_type_code(predicate_subject_token[impl_node]);
    if (!exact_impl_key_type_supported(subject_ty))
        return false;

    uint arg_count = predicate_bound_arg_count[impl_node];
    if (arg_count > 2u)
        return false;

    if (arg_count >= 1u)
    {
        uint arg0_ty = predicate_arg_type_code(predicate_bound_first_arg_token[impl_node]);
        if (!exact_impl_key_type_supported(arg0_ty))
            return false;
    }

    if (arg_count >= 2u)
    {
        uint arg1_ty = predicate_arg_type_code(predicate_bound_second_arg_token[impl_node]);
        if (!exact_impl_key_type_supported(arg1_ty))
            return false;
    }

    return true;
}

bool impl_row_satisfies_bound(
    uint impl_node,
    uint bound_decl_id,
    uint subject_ty,
    uint required_arg0_ty,
    uint required_arg1_ty,
    uint arg_count)
{
    if (!impl_row_has_supported_exact_key(impl_node))
        return false;
    if (bound_decl_id == INVALID || predicate_bound_decl_id[impl_node] != bound_decl_id)
        return false;
    uint impl_subject_ty = predicate_type_code(predicate_subject_token[impl_node]);
    if (impl_subject_ty != subject_ty)
        return false;
    if (predicate_bound_arg_count[impl_node] != arg_count)
        return false;
    if (arg_count >= 1u)
    {
        uint impl_arg0_ty = predicate_arg_type_code(predicate_bound_first_arg_token[impl_node]);
        if (impl_arg0_ty == TY_UNKNOWN || impl_arg0_ty != required_arg0_ty)
            return false;
    }
    if (arg_count >= 2u)
    {
        uint impl_arg1_ty = predicate_arg_type_code(predicate_bound_second_arg_token[impl_node]);
        if (impl_arg1_ty == TY_UNKNOWN || impl_arg1_ty != required_arg1_ty)
            return false;
    }
    return true;
}

uint impl_index_match_count(
    uint bound_decl_id,
    uint subject_ty,
    uint required_arg0_ty,
    uint required_arg1_ty,
    uint arg_count,
    out uint first_match)
{
    first_match = INVALID;
    uint predicate_count = active_sorted_predicate_count();
    if (predicate_count == 0u)
        return 0u;

    uint bucket = predicate_impl_lookup_bucket(
        bound_decl_id,
        subject_ty,
        arg_count,
        required_arg0_ty,
        required_arg1_ty,
        predicate_count);
    uint link = predicate_impl_lookup_head[bucket];
    uint visited = 0u;
    uint matches = 0u;
    uint first_token = INVALID;
    while (link != 0u && visited < predicate_count)
    {
        uint impl_node = link - 1u;
        if (!valid_node(impl_node))
            return INVALID;
        if (impl_row_satisfies_bound(
                impl_node,
                bound_decl_id,
                subject_ty,
                required_arg0_ty,
                required_arg1_ty,
                arg_count))
        {
            matches += 1u;
            uint token = compact_hir_core[impl_node].token_start;
            if (first_match == INVALID || token < first_token ||
                (token == first_token && impl_node < first_match))
            {
                first_match = impl_node;
                first_token = token;
            }
        }
        link = predicate_impl_lookup_next[impl_node];
        visited += 1u;
    }

    return link == 0u ? matches : INVALID;
}

uint concrete_impl_match_count_for_bound(
    uint bound_decl_id,
    uint subject_ty,
    uint required_arg0_ty,
    uint required_arg1_ty,
    uint arg_count)
{
    if (bound_decl_id >= active_hir_node_count())
        return 0u;
    if (!exact_impl_key_type_supported(subject_ty))
        return 0u;
    if (arg_count >= 1u && !exact_impl_key_type_supported(required_arg0_ty))
        return 0u;
    if (arg_count >= 2u && !exact_impl_key_type_supported(required_arg1_ty))
        return 0u;

    uint first_match;
    return impl_index_match_count(
        bound_decl_id,
        subject_ty,
        required_arg0_ty,
        required_arg1_ty,
        arg_count,
        first_match);
}

void validate_unique_impl_key(uint impl_node)
{
    if (!valid_node(impl_node) ||
        predicate_owner_node[impl_node] != impl_node ||
        predicate_status[impl_node] != PREDICATE_STATUS_OK)
        return;

    if (!impl_row_has_supported_exact_key(impl_node))
    {
        uint token_i = valid_token(compact_hir_core[impl_node].token_start)
            ? compact_hir_core[impl_node].token_start
            : 0u;
        record_error(
            token_i,
            ERR_INVALID_TRAIT_IMPLEMENTATION,
            PREDICATE_STATUS_INVALID_IMPL_ARG);
        return;
    }

    uint subject_ty = predicate_type_code(predicate_subject_token[impl_node]);

    uint arg_count = predicate_bound_arg_count[impl_node];

    uint bound_decl_id = predicate_bound_decl_id[impl_node];
    uint arg0_ty = arg_count >= 1u
        ? predicate_arg_type_code(predicate_bound_first_arg_token[impl_node])
        : TY_UNKNOWN;
    uint arg1_ty = arg_count >= 2u
        ? predicate_arg_type_code(predicate_bound_second_arg_token[impl_node])
        : TY_UNKNOWN;
    uint first_match;
    uint match_count = impl_index_match_count(
        bound_decl_id,
        subject_ty,
        arg0_ty,
        arg1_ty,
        arg_count,
        first_match);
    if (match_count == INVALID || match_count == 0u)
    {
        uint token_i = valid_token(compact_hir_core[impl_node].token_start)
            ? compact_hir_core[impl_node].token_start
            : 0u;
        record_error(
            token_i,
            ERR_INVALID_TRAIT_IMPLEMENTATION,
            PREDICATE_STATUS_OVERLAPPING_IMPL);
        return;
    }
    if (match_count <= 1u)
        return;

    if (first_match == impl_node)
        return;

    uint token_i = valid_token(compact_hir_core[impl_node].token_start)
        ? compact_hir_core[impl_node].token_start
        : 0u;
    record_error(
        token_i,
        ERR_INVALID_TRAIT_IMPLEMENTATION,
        PREDICATE_STATUS_OVERLAPPING_IMPL);
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

    bool trait_bound_status =
        status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH ||
        status_value == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE ||
        status_value == PREDICATE_STATUS_INVALID_ARG ||
        (!trait_contract_node &&
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

void validate_trait_obligation_for_call(uint pred, uint fn_node, uint node)
{
    if (compact_hir_core[node].kind != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(node);
    if (!valid_token(callee_token))
        return;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token))
        return;

    if (!valid_node(fn_node) || canonical_function_token(fn_node) != fn_token)
        return;

    uint subject_token = predicate_subject_token[pred];
    uint subject_slot = generic_param_slot_for_name(fn_node, subject_token);
    if (subject_slot == INVALID)
    {
        record_error(callee_token, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_SUBJECT);
        return;
    }

    uint subject_failure_detail = PREDICATE_STATUS_OK;
    uint subject_ty = actual_type_for_generic_slot_with_detail(
        node,
        fn_node,
        subject_slot,
        subject_failure_detail);
    if (subject_ty == TY_UNKNOWN)
    {
        record_error(
            callee_token,
            ERR_TRAIT_BOUND_UNSATISFIED,
            subject_failure_detail == PREDICATE_STATUS_OK
                ? PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW
                : subject_failure_detail);
        return;
    }

    uint arg_count = predicate_bound_arg_count[pred];
    if (arg_count > 2u)
    {
        record_error(
            callee_token,
            ERR_TRAIT_BOUND_UNSATISFIED,
            PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH);
        return;
    }

    uint required_arg0_ty = TY_UNKNOWN;
    uint required_arg1_ty = TY_UNKNOWN;
    if (arg_count >= 1u)
    {
        required_arg0_ty = predicate_arg_concrete_type(pred, fn_node, node, 0u);
        if (required_arg0_ty == TY_UNKNOWN)
        {
            record_error(
                callee_token,
                ERR_TRAIT_BOUND_UNSATISFIED,
                PREDICATE_STATUS_INVALID_ARG);
            return;
        }
    }
    if (arg_count >= 2u)
    {
        required_arg1_ty = predicate_arg_concrete_type(pred, fn_node, node, 1u);
        if (required_arg1_ty == TY_UNKNOWN)
        {
            record_error(
                callee_token,
                ERR_TRAIT_BOUND_UNSATISFIED,
                PREDICATE_STATUS_INVALID_ARG);
            return;
        }
    }

    uint impl_count = concrete_impl_match_count_for_bound(
        predicate_bound_decl_id[pred],
        subject_ty,
        required_arg0_ty,
        required_arg1_ty,
        arg_count);
    if (impl_count != 1u)
    {
        bool unsatisfied = impl_count == 0u;
        record_error(
            callee_token,
            unsatisfied ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_TRAIT_BOUND_AMBIGUOUS,
            unsatisfied ? PREDICATE_STATUS_UNSATISFIED_BOUND
                        : PREDICATE_STATUS_AMBIGUOUS_BOUND);
        return;
    }
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
