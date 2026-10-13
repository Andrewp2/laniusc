import type_checker.constant_parameter_slots;
import type_checker.calls.checked_constant_environment;
// Compact-HIR array call-result validation.
//
// This pass runs after bounded generic array call inference. It keeps
// array-valued call results length-aware by comparing the annotated destination
// declaration's array instance with either the callee's declared return array
// instance or the declaration-backed actual array argument instance. It consumes
// dense statement/call payloads and type-instance refs; it does not inspect
// source bytes, token spelling, helper
// names, or callee function bodies. Over-width call/parameter windows fail
// closed before bounded cache slots are consumed.

import hir_records;
import external_type_identity;
import type_checker.concrete_type_equality;
import type_checker.instance_arguments;
import type_checker.calls.claim_lookup;
import type_checker.calls.checked_call_environment;
import type_checker.scoped_type_equality;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_row_ordinal;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_arg_param_row;
RWStructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> method_call_name_id;

StructuredBuffer<uint> call_return_generic_slot;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_EXPR_NAME = 2u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;

static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

public struct CheckedConcreteTypeGraph : IScopedTypeGraph
{
    public static uint constant_parameter_slot(uint token) { return type_const_param_slot_by_token[token]; }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { return checked_call_environment_constant_ref(environment, slot, kind, value); }
    public static uint parameter_slot(uint token)
    { return type_generic_param_slot_by_token[token]; }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { return checked_call_environment_argument(environment, slot, tag, payload); }
    public static uint metadata(uint instance, uint field)
    {
        switch (field)
        {
        case 0u: return type_instance_kind[instance];
        case 1u: return type_instance_decl_token[instance];
        case 2u: return type_instance_arg_count[instance];
        case 3u: return type_instance_elem_ref_tag[instance];
        case 4u: return type_instance_elem_ref_payload[instance];
        case 5u: return type_instance_len_kind[instance];
        case 6u: return type_instance_len_payload[instance];
        case 7u: return external_type_library_id[instance];
        case 8u: return external_type_unit_id[instance];
        case 9u: return external_type_local_index[instance];
        default: return INVALID;
        }
    }

    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        uint source_capacity; uint stride;
        type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
        return checked_instance_argument(instance, slot, source_capacity,
            type_instance_arg_count, type_instance_arg_start,
            type_instance_arg_ref_tag, type_instance_arg_ref_payload,
            type_instance_arg_row_start, type_instance_arg_row_count_out,
            type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload, tag, payload);
    }
}


uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint type_capacity()
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return capacity;
}

bool valid_instance(uint instance) { return instance < type_capacity(); }

uint stmt_slot(uint node, uint slot)
{
    if (!valid_node(node)) return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == 0u) return payload.a;
    if (slot == 1u) return payload.b;
    if (slot == 2u) return payload.c;
    return payload.d;
}

uint expr_slot(uint node, uint slot)
{
    if (!valid_node(node)) return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == 0u) return payload.a;
    if (slot == 1u) return payload.b;
    if (slot == 2u) return payload.c;
    return payload.d;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    return node;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         expr_slot(node, 0u) != HIR_EXPR_NAME))
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

bool is_symbolic_array_type(uint ty)
{
    return ty == TY_ARRAY_BASE + TY_UNKNOWN ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return INVALID;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint token = callee.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token)) token = callee.token_start;
    return valid_token(token) ? token : INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
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

uint first_call_arg_name_token(uint callee_token, uint call_node)
{
    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint arg_node_token = name_token_for_expr(arg_node);
    if (valid_token(arg_node_token))
        return arg_node_token;

    if (valid_token(callee_token))
    {
        uint arg_token = call_arg_record[callee_token].x;
        if (valid_token(arg_token))
            return arg_token;
    }

    return INVALID;
}

uint call_arg_count_for_callee(uint callee_token, uint call_node)
{
    if (!valid_token(callee_token))
        return 0u;
    uint record_count = call_arg_record[callee_token].w;
    if (!valid_node(call_node))
        return record_count;
    return max(max(record_count, compact_hir_payload[call_node].c), call_arg_row_count[call_node]);
}

bool call_window_fits_cache(uint callee_token, uint call_node)
{
    uint fn_token = valid_token(callee_token) ? call_fn_index[callee_token] : INVALID;
    if (!valid_token(fn_token))
        return true;

    uint param_count = call_param_count[fn_token];
    uint arg_count = call_arg_count_for_callee(callee_token, call_node);
    if (param_count == arg_count)
        return true;

    call_return_type[callee_token] = TY_UNKNOWN;
    record_min_token_error(
        status,
        callee_token,
        ERR_CALL_MISMATCH,
        CALL_MISMATCH_ARITY);
    return false;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_instance(payload))
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;

    uint len_kind = type_instance_len_kind[payload];
    if (len_kind != TYPE_LEN_LITERAL && len_kind != TYPE_LEN_CONST_PARAM)
        return INVALID;
    return payload;
}

uint array_instance_from_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl_token],
        decl_type_ref_payload[decl_token]);
}

uint array_instance_from_name_token(uint name_token)
{
    if (!valid_token(name_token))
        return INVALID;
    uint decl_token = visible_decl[name_token];
    uint instance = array_instance_from_decl_token(decl_token);
    return instance != INVALID || decl_token == name_token
        ? instance
        : array_instance_from_decl_token(name_token);
}

uint array_instance_from_callee_return(uint callee_token)
{
    if (!valid_token(callee_token))
        return INVALID;

    uint decl_token = call_fn_index[callee_token];
    if (!valid_token(decl_token))
        decl_token = visible_decl[callee_token];
    if (!valid_token(decl_token))
        decl_token = callee_token;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[decl_token],
        fn_return_ref_payload[decl_token]);
}

uint array_instance_from_call_param_row(uint param_row)
{
    if (param_row == INVALID || param_row >= call_param_row_count_out[0u])
        return INVALID;
    return bounded_array_instance_from_ref(
        call_param_row_ref_tag[param_row],
        call_param_row_ref_payload[param_row]);
}

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag == TYPE_REF_SCALAR || rhs_tag == TYPE_REF_SCALAR)
        return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
    if (lhs_tag == TYPE_REF_GENERIC_PARAM && rhs_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint lhs_slot = valid_token(lhs_payload) ? type_generic_param_slot_by_token[lhs_payload] : INVALID;
        uint rhs_slot = valid_token(rhs_payload) ? type_generic_param_slot_by_token[rhs_payload] : INVALID;
        return lhs_slot != INVALID && lhs_slot == rhs_slot;
    }
    return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
}

bool concrete_array_elem_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return true;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return false;
    return tag == TYPE_REF_INSTANCE && valid_instance(payload);
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

uint array_type_code_from_instance(uint instance)
{
    if (!valid_instance(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return TY_UNKNOWN;
    uint elem_ty = type_code_for_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
    return elem_ty == TY_UNKNOWN ? TY_UNKNOWN : TY_ARRAY_BASE + elem_ty;
}

bool same_array_len(uint lhs, uint rhs)
{
    uint lhs_kind = type_instance_len_kind[lhs];
    uint rhs_kind = type_instance_len_kind[rhs];
    if (lhs_kind != rhs_kind)
        return false;
    if (lhs_kind == TYPE_LEN_LITERAL)
        return type_instance_len_payload[lhs] == type_instance_len_payload[rhs];
    if (lhs_kind == TYPE_LEN_CONST_PARAM)
    {
        uint lhs_payload = type_instance_len_payload[lhs];
        uint rhs_payload = type_instance_len_payload[rhs];
        uint lhs_slot = valid_token(lhs_payload) ? type_const_param_slot_by_token[lhs_payload] : INVALID;
        uint rhs_slot = valid_token(rhs_payload) ? type_const_param_slot_by_token[rhs_payload] : INVALID;
        return lhs_slot != INVALID && lhs_slot == rhs_slot;
    }
    return false;
}

bool concrete_bounded_array_instance(uint instance)
{
    if (!valid_instance(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return false;
    if (type_instance_len_kind[instance] != TYPE_LEN_LITERAL)
        return false;
    return concrete_array_elem_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

bool same_bounded_array_instance(uint lhs, uint rhs)
{
    if (!valid_instance(lhs) || !valid_instance(rhs))
        return false;
    if (type_instance_kind[lhs] != TYPE_INSTANCE_ARRAY ||
        type_instance_kind[rhs] != TYPE_INSTANCE_ARRAY)
        return false;
    return concrete_type_refs_equal<CheckedConcreteTypeGraph>(
        TYPE_REF_INSTANCE, lhs, TYPE_REF_INSTANCE, rhs, type_capacity());
}

bool array_elem_matches_call_environment(
    uint callee_token,
    uint expected_instance,
    uint actual_instance)
{
    uint expected_tag = type_instance_elem_ref_tag[expected_instance];
    uint expected_payload = type_instance_elem_ref_payload[expected_instance];
    uint actual_tag = type_instance_elem_ref_tag[actual_instance];
    uint actual_payload = type_instance_elem_ref_payload[actual_instance];

    // Parameter inference has accepted complete bindings. Compare the entire
    // element under that environment, including nominal arguments and nested
    // array/slice elements; scalar cache codes cannot represent these facts.
    return scoped_type_refs_equal<CheckedConcreteTypeGraph>(
        expected_tag, expected_payload, 0x80000000u | callee_token,
        actual_tag, actual_payload, INVALID, type_capacity(), gParams.n_tokens);
}

bool array_len_matches_call_state(
    uint row,
    uint callee_token,
    uint expected_instance,
    uint actual_instance)
{
    uint expected_kind = type_instance_len_kind[expected_instance];
    uint expected_payload = type_instance_len_payload[expected_instance];
    uint actual_kind = type_instance_len_kind[actual_instance];
    uint actual_payload = type_instance_len_payload[actual_instance];

    if (expected_kind == TYPE_LEN_LITERAL)
        return actual_kind == TYPE_LEN_LITERAL && actual_payload == expected_payload;

    if (expected_kind != TYPE_LEN_CONST_PARAM)
        return false;

    uint slot = valid_token(expected_payload)
        ? type_const_param_slot_by_token[expected_payload]
        : INVALID;
    if (slot == INVALID)
        return false;

    uint inferred_kind; uint inferred;
    return checked_call_environment_constant_ref(0x80000000u | callee_token, slot,
        inferred_kind, inferred) && inferred_kind == actual_kind && inferred == actual_payload;
}

bool array_instance_matches_call_state(
    uint row,
    uint callee_token,
    uint expected_instance,
    uint actual_instance)
{
    if (!valid_instance(expected_instance) || !valid_instance(actual_instance))
        return false;
    if (type_instance_kind[expected_instance] != TYPE_INSTANCE_ARRAY ||
        type_instance_kind[actual_instance] != TYPE_INSTANCE_ARRAY)
        return false;
    if (!concrete_bounded_array_instance(actual_instance))
        return false;
    return array_elem_matches_call_environment(callee_token, expected_instance, actual_instance) &&
           array_len_matches_call_state(row, callee_token, expected_instance, actual_instance);
}

void validate_array_call_arg_row(uint row)
{
    if (row >= call_arg_row_count_out[0])
        return;

    uint call_node = call_arg_row_call_node[row];
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;
    if (method_call_name_id[callee_token] != INVALID)
        return;

    uint expected_instance = array_instance_from_call_param_row(call_arg_param_row[row]);
    if (expected_instance == INVALID)
        return;
    if (!call_window_fits_cache(callee_token, call_node))
        return;

    uint arg_node = call_arg_row_node[row];
    uint actual_instance = array_instance_from_name_token(name_token_for_expr(arg_node));
    if (!concrete_bounded_array_instance(actual_instance))
        return;
    if (array_instance_matches_call_state(row, callee_token, expected_instance, actual_instance))
        return;

    record_min_token_error(
        status,
        callee_token,
        ERR_ASSIGN_MISMATCH,
        TY_ARRAY_BASE * 256u + TY_UNKNOWN);
}

uint direct_generic_array_result(uint callee)
{
    uint function = call_fn_index[callee];
    if (!valid_token(function)) return INVALID;
    uint slot = call_return_generic_slot[function];
    uint count = call_generic_claim_count_out[0u];
    if (slot == INVALID || count == 0u) return INVALID;
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    uint accepted = INVALID;
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) break;
        if (call_generic_claim_callee[row] == callee && call_generic_claim_slot[row] == slot &&
            call_generic_claim_ref_tag[row] == TYPE_REF_INSTANCE)
            accepted = min(accepted, row);
        link = call_generic_claim_lookup_next[row];
    }
    if (accepted == INVALID) return INVALID;
    uint instance = call_generic_claim_ref_payload[accepted];
    return valid_instance(instance) && type_instance_kind[instance] == TYPE_INSTANCE_ARRAY
        ? instance : INVALID;
}

void validate_array_call_let(uint node)
{
    if (!valid_node(node) ||
        stmt_slot(node, 0u) != STMT_RECORD_KIND_LET)
        return;

    uint decl_token = stmt_slot(node, 1u);
    uint expected_ty = valid_token(decl_token) ? visible_type[decl_token] : TY_UNKNOWN;
    uint expected_instance = array_instance_from_decl_token(decl_token);
    if (expected_instance != INVALID)
    {
        uint instance_ty = array_type_code_from_instance(expected_instance);
        if (instance_ty != TY_UNKNOWN)
            expected_ty = instance_ty;
    }
    if (expected_instance == INVALID && !is_array_type(expected_ty))
        return;

    uint expr_node = stmt_slot(node, 2u);
    uint call_node = resolve_expr(expr_node);
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;
    if (method_call_name_id[callee_token] != INVALID)
        return;
    if (!call_window_fits_cache(callee_token, call_node))
        return;
    uint checked_result = call_result_instance[call_node];
    if (expected_instance != INVALID && valid_instance(checked_result) &&
        type_instance_kind[checked_result] == TYPE_INSTANCE_ARRAY)
    {
        // Complete local/imported return materialization is authoritative.
        // A dependency callee has no local fn_return_ref row to compare.
        if (!concrete_type_refs_equal<CheckedConcreteTypeGraph>(TYPE_REF_INSTANCE, expected_instance,
            TYPE_REF_INSTANCE, checked_result, type_capacity()))
            record_min_token_error(status, callee_token, ERR_ASSIGN_MISMATCH,
                TY_ARRAY_BASE * 256u + call_return_type[callee_token]);
        return;
    }
    uint generic_instance = direct_generic_array_result(callee_token);
    if (generic_instance != INVALID && expected_instance != INVALID)
    {
        if (concrete_type_refs_equal<CheckedConcreteTypeGraph>(TYPE_REF_INSTANCE, expected_instance,
                TYPE_REF_INSTANCE, generic_instance, type_capacity()))
        {
            call_result_instance[call_node] = generic_instance;
            return;
        }
        record_min_token_error(status, callee_token, ERR_ASSIGN_MISMATCH,
            TY_ARRAY_BASE * 256u + call_return_type[callee_token]);
        return;
    }
    if (!is_array_type(call_return_type[callee_token]))
        return;

    uint actual_ty = call_return_type[callee_token];
    bool specialize_symbolic_result = is_symbolic_array_type(actual_ty);
    if (specialize_symbolic_result && expected_ty != TY_UNKNOWN)
        call_return_type[callee_token] = expected_ty;
    if (expected_instance == INVALID)
        return;

    uint declared_instance = array_instance_from_callee_return(callee_token);
    if (declared_instance != INVALID &&
        same_bounded_array_instance(expected_instance, declared_instance))
    {
        return;
    }

    uint actual_instance = INVALID;
    if (declared_instance != INVALID)
    {
        actual_instance = call_result_instance[call_node];
    }
    else if (specialize_symbolic_result)
    {
        actual_instance =
            array_instance_from_name_token(first_call_arg_name_token(callee_token, call_node));
    }
    if (actual_instance != INVALID &&
        same_bounded_array_instance(expected_instance, actual_instance))
    {
        return;
    }

    record_min_token_error(
        status,
        valid_token(callee_token) ? callee_token : decl_token,
        ERR_ASSIGN_MISMATCH,
        TY_ARRAY_BASE * 256u + actual_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    validate_array_call_let(node);
    validate_array_call_arg_row(node);
}
