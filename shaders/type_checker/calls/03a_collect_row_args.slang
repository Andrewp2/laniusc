// Row-dispatched direct call argument validation and generic inference.
//
// Argument-to-parameter matching is built before this pass by the compact
// linked-list matcher. This pass consumes that relation and owns validation,
// generic claim marking, and per-argument diagnostics.

import atomics;
import hir_expr_semantics;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_param_row;
RWStructuredBuffer<uint> call_generic_claim_scan_input;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> call_generic_slot_type;
RWStructuredBuffer<uint> call_generic_slot_ordinal;
RWStructuredBuffer<uint> call_generic_return_arg_node;
RWStructuredBuffer<uint> call_const_slot_len;
RWStructuredBuffer<uint> call_generic_claim_callee;
RWStructuredBuffer<uint> call_generic_claim_slot;
RWStructuredBuffer<uint> call_generic_claim_type;
RWStructuredBuffer<uint> call_generic_claim_ref_tag;
RWStructuredBuffer<uint> call_generic_claim_ref_payload;
RWStructuredBuffer<uint> call_generic_claim_order;
RWStructuredBuffer<uint> call_const_claim_callee;
RWStructuredBuffer<uint> call_const_claim_slot;
RWStructuredBuffer<uint> call_const_claim_len;
RWStructuredBuffer<uint> call_const_claim_order;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
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
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_REF_EXTERNAL_GENERIC = 6u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
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
    return token != INVALID && token < active_token_count();
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return true;
    if (dst == src)
        return true;
    if (dst == TY_INT)
        return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT)
        return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT)
        return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    return false;
}

bool is_symbolic_array_type(uint ty)
{
    return ty == TY_ARRAY_BASE + TY_UNKNOWN ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint plain_generic_slot(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty < TY_GENERIC_BASE + PARAM_CACHE_STRIDE
        ? ty - TY_GENERIC_BASE
        : INVALID;
}

uint array_or_slice_generic_slot(uint ty)
{
    return ty >= TY_ARRAY_BASE + TY_GENERIC_BASE &&
           ty < TY_ARRAY_BASE + TY_GENERIC_BASE + PARAM_CACHE_STRIDE
        ? ty - TY_ARRAY_BASE - TY_GENERIC_BASE
        : INVALID;
}

uint expr_record_slot(uint node, uint slot)
{
    if (!valid_node(node))
        return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == HIR_EXPR_RECORD_FORM) return payload.a;
    if (slot == HIR_EXPR_RECORD_LEFT) return payload.b;
    if (slot == HIR_EXPR_RECORD_RIGHT) return payload.c;
    return payload.d;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint current = node;
    for (uint step = 0u; step < 32u && valid_node(current); step += 1u)
    {
        if (expr_form(current) != HIR_EXPR_FORWARD)
            return current;
        uint next = expr_record_slot(current, HIR_EXPR_RECORD_LEFT);
        if (!valid_node(next) || next == current)
            return current;
        current = next;
    }
    return current;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token];
}

uint inferred_call_return_type(uint callee_token)
{
    if (!valid_token(callee_token))
        return TY_UNKNOWN;

    uint ret_ty = call_return_type[callee_token];
    uint slot = plain_generic_slot(ret_ty);
    if (slot != INVALID)
    {
        uint inferred = call_generic_slot_type[callee_token * PARAM_CACHE_STRIDE + slot];
        return inferred == INVALID ? TY_UNKNOWN : inferred;
    }

    slot = array_or_slice_generic_slot(ret_ty);
    if (slot != INVALID)
    {
        uint inferred = call_generic_slot_type[callee_token * PARAM_CACHE_STRIDE + slot];
        return inferred == INVALID ? TY_UNKNOWN : TY_ARRAY_BASE + inferred;
    }

    return is_generic_type(ret_ty) ? TY_UNKNOWN : ret_ty;
}

uint callee_token_for_hir_call(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = compact_hir_core[call_node].token_start;
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
    {
        return valid_token(call_token) ? call_token : INVALID;
    }

    if (compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_node].c;
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = compact_hir_payload[callee_node].d;
    if (!valid_token(callee_token))
        callee_token = compact_hir_core[callee_node].token_start;
    if (!valid_token(callee_token))
        callee_token = compact_hir_core[call_node].token_start;
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint direct_node_type_no_nested_call(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = hir_scalar_type_for_expr_form(expr_form(node));
    if (lit != TY_UNKNOWN)
        return lit;

    uint token = compact_hir_core[node].token_start;
    if (compact_hir_core[node].kind == HIR_NAME_EXPR)
    {
        uint value_token = expr_value_token(node);
        if (valid_token(value_token))
            token = value_token;
        return visible_type_for_token(token);
    }

    if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[node].c;
        return visible_type_for_token(member_token);
    }

    if (compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR)
        return visible_type_for_token(compact_hir_core[node].token_start);

    if (compact_hir_core[node].kind == HIR_INDEX_EXPR ||
        compact_hir_core[node].kind == HIR_MATCH_EXPR)
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;

    if (compact_hir_core[node].kind == HIR_CALL_EXPR)
    {
        uint callee_token = callee_token_for_hir_call(node);
        if (!valid_token(callee_token))
            callee_token = compact_hir_core[node].token_start;
        return inferred_call_return_type(callee_token);
    }

    return TY_UNKNOWN;
}

uint expr_type_no_nested_call(uint result_node)
{
    uint node = resolve_expr(result_node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint direct_ty = direct_node_type_no_nested_call(node);
    if (direct_ty != TY_UNKNOWN)
        return direct_ty;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_value_token(node);
        if (!valid_token(token))
            token = compact_hir_core[node].token_start;
        return visible_type_for_token(token);
    }

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
        uint left_ty = direct_node_type_no_nested_call(resolve_expr(expr_record_slot(node, HIR_EXPR_RECORD_LEFT)));
        uint right_ty = direct_node_type_no_nested_call(resolve_expr(expr_record_slot(node, HIR_EXPR_RECORD_RIGHT)));
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

uint generic_slot_for_type_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_EXTERNAL_GENERIC)
        return payload;
    if (tag != TYPE_REF_GENERIC_PARAM || !valid_token(payload))
        return INVALID;
    return type_generic_param_slot_by_token[payload];
}

uint leaf_type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    uint slot = generic_slot_for_type_ref(tag, payload);
    return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
}

uint instance_arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

uint instance_arg_row_ref_index(uint instance_i, uint ordinal)
{
    uint start = type_instance_arg_row_start[instance_i];
    uint ref_i = start == INVALID ? INVALID : start + ordinal;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance_i, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i))
        return false;
    if (type_instance_kind[instance_i] != TYPE_INSTANCE_NAMED)
        return false;
    if (ordinal >= type_instance_arg_count[instance_i])
        return false;

    uint row_ref_i = instance_arg_row_ref_index(instance_i, ordinal);
    if (row_ref_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_ref_i];
        payload = type_instance_arg_row_ref_payload[row_ref_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint fixed_ref_i = instance_arg_ref_index(instance_i, ordinal);
    if (fixed_ref_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[fixed_ref_i];
    payload = type_instance_arg_ref_payload[fixed_ref_i];
    return tag != TYPE_REF_INVALID;
}

bool param_instance_ref_for_row(uint param_row, out uint instance_i)
{
    instance_i = INVALID;
    if (param_row == INVALID || call_param_row_ref_tag[param_row] != TYPE_REF_INSTANCE)
        return false;

    uint payload = call_param_row_ref_payload[param_row];
    if (!valid_token(payload) || type_instance_kind[payload] != TYPE_INSTANCE_NAMED)
        return false;

    instance_i = payload;
    return true;
}

uint param_array_or_slice_generic_slot_for_row(uint param_row)
{
    if (param_row == INVALID || call_param_row_ref_tag[param_row] != TYPE_REF_INSTANCE)
        return INVALID;

    uint instance_i = call_param_row_ref_payload[param_row];
    if (!valid_token(instance_i))
        return INVALID;

    uint kind = type_instance_kind[instance_i];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return INVALID;

    return generic_slot_for_type_ref(
        type_instance_elem_ref_tag[instance_i],
        type_instance_elem_ref_payload[instance_i]);
}

uint param_array_or_slice_generic_token_for_row(uint param_row)
{
    if (param_row == INVALID || call_param_row_ref_tag[param_row] != TYPE_REF_INSTANCE)
        return INVALID;

    uint instance_i = call_param_row_ref_payload[param_row];
    if (!valid_token(instance_i))
        return INVALID;

    uint kind = type_instance_kind[instance_i];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return INVALID;

    uint payload = type_instance_elem_ref_payload[instance_i];
    return type_instance_elem_ref_tag[instance_i] == TYPE_REF_GENERIC_PARAM &&
           valid_token(payload)
        ? payload
        : INVALID;
}

uint param_array_const_len_slot_for_row(uint param_row)
{
    if (param_row == INVALID || call_param_row_ref_tag[param_row] != TYPE_REF_INSTANCE)
        return INVALID;

    uint instance_i = call_param_row_ref_payload[param_row];
    if (!valid_token(instance_i) || type_instance_kind[instance_i] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    if (type_instance_len_kind[instance_i] != TYPE_LEN_CONST_PARAM)
        return INVALID;

    uint payload = type_instance_len_payload[instance_i];
    return valid_token(payload) ? type_const_param_slot_by_token[payload] : INVALID;
}

uint param_instance_generic_slot_for_row(uint param_row, uint instance_arg_ordinal)
{
    uint instance_i;
    if (!param_instance_ref_for_row(param_row, instance_i))
        return INVALID;

    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, instance_arg_ordinal, tag, payload))
        return INVALID;

    return generic_slot_for_type_ref(tag, payload);
}

uint param_instance_generic_token_for_row(uint param_row, uint instance_arg_ordinal)
{
    uint instance_i;
    if (!param_instance_ref_for_row(param_row, instance_i))
        return INVALID;

    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, instance_arg_ordinal, tag, payload))
        return INVALID;

    return tag == TYPE_REF_GENERIC_PARAM && valid_token(payload)
        ? payload
        : INVALID;
}

uint param_direct_generic_token_for_row(uint param_row)
{
    if (param_row == INVALID || call_param_row_ref_tag[param_row] != TYPE_REF_GENERIC_PARAM)
        return INVALID;
    uint payload = call_param_row_ref_payload[param_row];
    return valid_token(payload) ? payload : INVALID;
}

uint param_direct_generic_slot_for_row(uint param_row)
{
    if (param_row == INVALID)
        return INVALID;
    return generic_slot_for_type_ref(
        call_param_row_ref_tag[param_row],
        call_param_row_ref_payload[param_row]);
}

void claim_return_generic_token(
    uint callee_i,
    uint fn_i,
    uint generic_token,
    uint arg_ty,
    uint arg_token)
{
    if (!valid_token(callee_i) ||
        !valid_token(fn_i) ||
        !valid_token(generic_token) ||
        arg_ty == TY_UNKNOWN)
    {
        return;
    }

    uint return_token = call_return_type_token[fn_i];
    if (return_token != generic_token)
    {
        uint return_slot = generic_slot_for_type_ref(TYPE_REF_GENERIC_PARAM, return_token);
        uint param_slot = generic_slot_for_type_ref(TYPE_REF_GENERIC_PARAM, generic_token);
        if (return_slot == INVALID || param_slot == INVALID || return_slot != param_slot)
            return;
    }

    uint expected = call_return_type[fn_i];
    if (!is_generic_type(expected))
        return;

    uint prior = atomic_u32_compare_exchange(
        call_return_type,
        callee_i,
        expected,
        arg_ty);
    if (prior != expected && prior != arg_ty)
        record_error(arg_token, ERR_ASSIGN_MISMATCH, prior * 256u + arg_ty);
}

uint direct_name_expr_token(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node))
        return INVALID;
    if (expr_form(node) != HIR_EXPR_NAME &&
        compact_hir_core[node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint token = expr_value_token(node);
    if (!valid_token(token))
        token = compact_hir_core[node].token_start;
    return valid_token(token) ? token : INVALID;
}

bool read_decl_type_ref(uint token_i, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token_i))
        return false;

    uint ref_token = token_i;
    uint decl = visible_decl[token_i];
    if (valid_token(decl))
        ref_token = decl;

    tag = decl_type_ref_tag[ref_token];
    payload = decl_type_ref_payload[ref_token];
    if (tag != TYPE_REF_INVALID)
        return true;

    if (ref_token != token_i)
    {
        tag = decl_type_ref_tag[token_i];
        payload = decl_type_ref_payload[token_i];
    }
    return tag != TYPE_REF_INVALID;
}

bool arg_decl_type_ref(uint arg_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    uint token = direct_name_expr_token(arg_node);
    return read_decl_type_ref(token, tag, payload);
}

bool same_named_instance_decl(uint expected_instance, uint actual_instance)
{
    if (!valid_token(expected_instance) || !valid_token(actual_instance))
        return false;
    if (type_instance_kind[expected_instance] != TYPE_INSTANCE_NAMED ||
        type_instance_kind[actual_instance] != TYPE_INSTANCE_NAMED)
        return false;

    uint expected_decl = type_instance_decl_token[expected_instance];
    uint actual_decl = type_instance_decl_token[actual_instance];
    if (valid_token(expected_decl) || valid_token(actual_decl))
        return valid_token(expected_decl) && expected_decl == actual_decl;
    uint expected_external = type_instance_external_canonical[expected_instance];
    return expected_external != INVALID &&
           expected_external == type_instance_external_canonical[actual_instance];
}

bool actual_arg_decl_instance_ref(uint arg_node, out uint actual_instance)
{
    actual_instance = INVALID;
    uint tag;
    uint payload;
    if (!arg_decl_type_ref(arg_node, tag, payload))
        return false;
    if (tag != TYPE_REF_INSTANCE ||
        !valid_token(payload) ||
        type_instance_kind[payload] != TYPE_INSTANCE_NAMED)
        return false;
    actual_instance = payload;
    return true;
}

bool actual_arg_call_return_instance_ref(uint arg_node, out uint actual_instance)
{
    actual_instance = INVALID;
    uint actual_call_node = resolve_expr(arg_node);
    if (!valid_node(actual_call_node) ||
        compact_hir_core[actual_call_node].kind != HIR_CALL_EXPR)
        return false;

    uint actual_callee = callee_token_for_hir_call(actual_call_node);
    if (!valid_token(actual_callee))
        return false;

    uint actual_fn = call_fn_index[actual_callee];
    if (!valid_token(actual_fn))
        return false;

    uint return_instance = call_return_type_token[actual_fn];
    if (!valid_token(return_instance) ||
        type_instance_kind[return_instance] != TYPE_INSTANCE_NAMED)
        return false;
    actual_instance = return_instance;
    return true;
}

bool actual_arg_instance_ref(uint arg_node, out uint actual_instance)
{
    if (actual_arg_decl_instance_ref(arg_node, actual_instance))
        return true;
    return actual_arg_call_return_instance_ref(arg_node, actual_instance);
}

uint array_or_slice_element_type_for_arg_node(uint arg_node)
{
    uint tag;
    uint payload;
    if (!arg_decl_type_ref(arg_node, tag, payload))
        return TY_UNKNOWN;
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return TY_UNKNOWN;

    uint kind = type_instance_kind[payload];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return TY_UNKNOWN;

    return leaf_type_code_for_ref(
        type_instance_elem_ref_tag[payload],
        type_instance_elem_ref_payload[payload]);
}

uint literal_array_len_for_arg_node(uint arg_node)
{
    uint tag;
    uint payload;
    if (!arg_decl_type_ref(arg_node, tag, payload))
        return INVALID;
    if (tag != TYPE_REF_INSTANCE ||
        !valid_token(payload) ||
        type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    return type_instance_len_kind[payload] == TYPE_LEN_LITERAL
        ? type_instance_len_payload[payload]
        : INVALID;
}

bool concrete_leaf_instance_arg_supported(uint instance_i, uint ordinal)
{
    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, ordinal, tag, payload))
        return true;
    return tag == TYPE_REF_SCALAR;
}

bool concrete_leaf_instance_supported(uint instance_i)
{
    if (!valid_token(instance_i) ||
        type_instance_arg_count[instance_i] > TYPE_INSTANCE_ARG_REF_STRIDE + 1u)
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 0u))
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 1u))
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 2u))
        return false;
    if (!concrete_leaf_instance_arg_supported(instance_i, 3u))
        return false;
    return concrete_leaf_instance_arg_supported(instance_i, 4u);
}

bool direct_call_instance_arg_relation_supported(uint instance_i, uint ordinal)
{
    if (!valid_token(instance_i))
        return false;

    uint arg_count = type_instance_arg_count[instance_i];
    if (ordinal >= arg_count)
        return true;

    uint tag;
    uint payload;
    if (!instance_arg_ref(instance_i, ordinal, tag, payload))
        return false;
    if (tag == TYPE_REF_INVALID ||
        tag == TYPE_REF_ERROR ||
        payload == INVALID)
        return false;

    if (tag == TYPE_REF_SCALAR)
        return payload != TY_UNKNOWN;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return generic_slot_for_type_ref(tag, payload) != INVALID;
    return false;
}

bool direct_call_instance_args_supported(uint instance_i)
{
    if (!valid_token(instance_i) ||
        type_instance_arg_count[instance_i] > TYPE_INSTANCE_ARG_REF_STRIDE + 1u)
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 0u))
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 1u))
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 2u))
        return false;
    if (!direct_call_instance_arg_relation_supported(instance_i, 3u))
        return false;
    return direct_call_instance_arg_relation_supported(instance_i, 4u);
}

uint actual_instance_arg_type(uint arg_node, uint expected_instance, uint instance_arg_ordinal)
{
    uint actual_tag;
    uint actual_payload;
    if (!arg_decl_type_ref(arg_node, actual_tag, actual_payload))
        return TY_UNKNOWN;
    if (actual_tag != TYPE_REF_INSTANCE ||
        !same_named_instance_decl(expected_instance, actual_payload))
        return TY_UNKNOWN;

    uint arg_tag;
    uint arg_payload;
    if (!instance_arg_ref(actual_payload, instance_arg_ordinal, arg_tag, arg_payload))
        return TY_UNKNOWN;
    return leaf_type_code_for_ref(arg_tag, arg_payload);
}

uint actual_call_return_instance_arg_type(
    uint arg_node,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint actual_call_node = resolve_expr(arg_node);
    if (!valid_node(actual_call_node) ||
        compact_hir_core[actual_call_node].kind != HIR_CALL_EXPR)
        return TY_UNKNOWN;

    uint actual_callee = callee_token_for_hir_call(actual_call_node);
    if (!valid_token(actual_callee))
        return TY_UNKNOWN;

    uint actual_fn = call_fn_index[actual_callee];
    if (!valid_token(actual_fn))
        return TY_UNKNOWN;

    uint return_instance = call_return_type_token[actual_fn];
    if (!same_named_instance_decl(expected_instance, return_instance))
        return TY_UNKNOWN;

    uint arg_tag;
    uint arg_payload;
    if (!instance_arg_ref(return_instance, instance_arg_ordinal, arg_tag, arg_payload))
        return TY_UNKNOWN;

    if (arg_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = generic_slot_for_type_ref(arg_tag, arg_payload);
        if (slot == INVALID || slot >= PARAM_CACHE_STRIDE)
            return TY_UNKNOWN;
        uint inferred = call_generic_slot_type[actual_callee * PARAM_CACHE_STRIDE + slot];
        return inferred == INVALID ? TY_UNKNOWN : inferred;
    }
    return leaf_type_code_for_ref(arg_tag, arg_payload);
}

uint actual_instance_or_call_return_arg_type(
    uint arg_node,
    uint expected_instance,
    uint instance_arg_ordinal)
{
    uint actual_ty = actual_instance_arg_type(
        arg_node,
        expected_instance,
        instance_arg_ordinal);
    if (actual_ty != TY_UNKNOWN)
        return actual_ty;
    return actual_call_return_instance_arg_type(
        arg_node,
        expected_instance,
        instance_arg_ordinal);
}

uint call_arg_error_token(uint arg_node, uint callee_i)
{
    return valid_node(arg_node) ? compact_hir_core[arg_node].token_start : callee_i;
}

bool concrete_leaf_instance_arg_matches(
    uint arg_node,
    uint expected_instance,
    uint ordinal)
{
    uint expected_tag;
    uint expected_payload;
    if (!instance_arg_ref(expected_instance, ordinal, expected_tag, expected_payload))
        return true;
    if (expected_tag != TYPE_REF_SCALAR)
        return true;

    uint actual_ty = actual_instance_or_call_return_arg_type(
        arg_node,
        expected_instance,
        ordinal);
    return actual_ty != TY_UNKNOWN && actual_ty == expected_payload;
}

bool check_concrete_instance_argument(
    uint callee_i,
    uint arg_node,
    uint param_row,
    uint param_ty)
{
    uint expected_instance;
    if (!param_instance_ref_for_row(param_row, expected_instance))
        return true;

    uint error_token = call_arg_error_token(arg_node, callee_i);
    if (!concrete_leaf_instance_supported(expected_instance))
        return true;

    if (!direct_call_instance_args_supported(expected_instance))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_ty);
        return false;
    }

    uint actual_instance;
    if (!actual_arg_instance_ref(arg_node, actual_instance))
        return true;

    if (!same_named_instance_decl(expected_instance, actual_instance) ||
        type_instance_arg_count[expected_instance] != type_instance_arg_count[actual_instance])
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_ty);
        return false;
    }

    if (!concrete_leaf_instance_arg_matches(arg_node, expected_instance, 0u) ||
        !concrete_leaf_instance_arg_matches(arg_node, expected_instance, 1u) ||
        !concrete_leaf_instance_arg_matches(arg_node, expected_instance, 2u) ||
        !concrete_leaf_instance_arg_matches(arg_node, expected_instance, 3u) ||
        !concrete_leaf_instance_arg_matches(arg_node, expected_instance, 4u))
    {
        record_error(error_token, ERR_ASSIGN_MISMATCH, param_ty);
        return false;
    }
    return true;
}

void clear_generic_claim(uint row)
{
    call_generic_claim_callee[row] = INVALID;
    call_generic_claim_slot[row] = INVALID;
    call_generic_claim_type[row] = TY_UNKNOWN;
    call_generic_claim_ref_tag[row] = TYPE_REF_INVALID;
    call_generic_claim_ref_payload[row] = INVALID;
    call_generic_claim_order[row] = row;
    call_const_claim_callee[row] = INVALID;
    call_const_claim_slot[row] = INVALID;
    call_const_claim_len[row] = INVALID;
    call_const_claim_order[row] = row;
}

void emit_generic_claim(uint row, uint callee_i, uint slot, uint arg_ty)
{
    if (!valid_token(callee_i) || slot == INVALID)
        return;

    call_generic_claim_callee[row] = callee_i;
    call_generic_claim_slot[row] = slot;
    call_generic_claim_type[row] = arg_ty;
    uint arg_node = row < call_arg_row_count_out[0u] ? call_arg_row_node[row] : INVALID;
    uint tag;
    uint payload;
    if (valid_node(arg_node) && arg_decl_type_ref(arg_node, tag, payload))
    {
        if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        {
            uint external = type_instance_external_canonical[payload];
            if (external != INVALID)
            {
                // Retain the local instance so return substitution preserves
                // concrete arguments. The scalar claim column carries the
                // stable external nominal identity.
                call_generic_claim_type[row] = external + 1u;
            }
            else
            {
                tag = TYPE_REF_INVALID;
                payload = INVALID;
            }
        }
        call_generic_claim_ref_tag[row] = tag;
        call_generic_claim_ref_payload[row] = payload;
    }
    else if (arg_ty != TY_UNKNOWN && arg_ty < TY_ARRAY_BASE)
    {
        call_generic_claim_ref_tag[row] = TYPE_REF_SCALAR;
        call_generic_claim_ref_payload[row] = arg_ty;
    }
}

void emit_const_claim(uint row, uint callee_i, uint slot, uint arg_len)
{
    if (!valid_token(callee_i) || slot == INVALID || arg_len == INVALID)
        return;

    call_const_claim_callee[row] = callee_i;
    call_const_claim_slot[row] = slot;
    call_const_claim_len[row] = arg_len;
}

uint instance_generic_claim_upper_bound(uint param_row)
{
    uint instance_i;
    if (!param_instance_ref_for_row(param_row, instance_i))
        return 0u;
    return type_instance_arg_count[instance_i];
}

uint generic_claim_count_for_param_row(uint param_row, uint param_ty)
{
    uint count = 0u;

    if (is_generic_type(param_ty))
    {
        if (param_direct_generic_slot_for_row(param_row) != INVALID)
            count += 1u;
        if (array_or_slice_generic_slot(param_ty) != INVALID)
            count += 1u;
    }

    if (param_array_or_slice_generic_slot_for_row(param_row) != INVALID)
        count += 1u;

    // A named type expression may be a transparent alias whose checked
    // semantic code is already scalar. Its source-level type arguments belong
    // to alias substitution; they are not nominal children to infer or compare
    // again at the call site.
    if (param_ty != TY_UNKNOWN && param_ty < TY_ARRAY_BASE && !is_generic_type(param_ty))
        return count;

    count += instance_generic_claim_upper_bound(param_row);
    return count;
}

void claim_generic_slot(
    uint callee_i,
    uint slot,
    uint arg_ty,
    uint arg_token,
    uint param_ordinal)
{
    if (slot >= PARAM_CACHE_STRIDE)
        return;

    uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
    if (arg_ty == TY_UNKNOWN)
    {
        uint prior_ordinal = atomic_u32_min(
            call_generic_slot_ordinal,
            state_i,
            param_ordinal);
        if (prior_ordinal == INVALID || param_ordinal < prior_ordinal)
            call_generic_slot_type[state_i] = INVALID;
        return;
    }

    uint prior_ordinal = atomic_u32_min(
        call_generic_slot_ordinal,
        state_i,
        param_ordinal);
    if (prior_ordinal == INVALID || param_ordinal < prior_ordinal)
    {
        call_generic_slot_type[state_i] = arg_ty;
        return;
    }

    uint prior = call_generic_slot_type[state_i];
    if (prior == INVALID)
    {
        if (prior_ordinal == param_ordinal)
            call_generic_slot_type[state_i] = arg_ty;
        return;
    }

    if (prior != INVALID && prior != arg_ty)
        record_error(arg_token, ERR_ASSIGN_MISMATCH, prior * 256u + arg_ty);
}

void claim_const_slot_len(uint callee_i, uint slot, uint arg_len, uint arg_token)
{
    uint detail = TY_ARRAY_BASE * 256u + TY_UNKNOWN;
    if (arg_len == INVALID)
    {
        record_error(arg_token, ERR_ASSIGN_MISMATCH, detail);
        return;
    }

    if (slot >= PARAM_CACHE_STRIDE)
        return;

    uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
    uint prior = atomic_u32_compare_exchange(
        call_const_slot_len,
        state_i,
        INVALID,
        arg_len);
    if (prior != INVALID && prior != arg_len)
        record_error(arg_token, ERR_ASSIGN_MISMATCH, detail);
}

void collect_instance_generic_arg(
    uint row,
    uint callee_i,
    uint arg_node,
    uint param_row,
    uint instance_arg_i,
    uint param_ordinal)
{
    uint slot = param_instance_generic_slot_for_row(param_row, instance_arg_i);
    if (slot == INVALID)
        return;

    uint expected_instance;
    if (!param_instance_ref_for_row(param_row, expected_instance))
        return;

    uint arg_ty = actual_instance_or_call_return_arg_type(
        arg_node,
        expected_instance,
        instance_arg_i);
    uint generic_token = param_instance_generic_token_for_row(param_row, instance_arg_i);
    if (valid_token(generic_token))
        claim_return_generic_token(
            callee_i,
            call_fn_index[callee_i],
            generic_token,
            arg_ty,
            call_arg_error_token(arg_node, callee_i));
    emit_generic_claim(row, callee_i, slot, arg_ty);
    claim_generic_slot(
        callee_i,
        slot,
        arg_ty,
        call_arg_error_token(arg_node, callee_i),
        param_ordinal);
}

void collect_row_argument(uint row)
{
    if (row >= call_arg_row_count_out[0])
        return;

    call_generic_claim_scan_input[row] = 0u;
    clear_generic_claim(row);

    uint call_node = call_arg_row_call_node[row];
    uint arg_node = call_arg_row_node[row];
    if (!valid_node(call_node) || !valid_node(arg_node))
        return;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint fn_i = call_fn_index[callee_i];
    if (!valid_token(fn_i))
        return;

    uint param_row = call_arg_param_row[row];
    if (param_row == INVALID)
        return;
    uint param_ordinal = call_param_row_ordinal[param_row];

    uint param_ty = call_param_row_type[param_row];
    uint arg_token = call_arg_error_token(arg_node, callee_i);
    call_generic_claim_scan_input[row] = generic_claim_count_for_param_row(param_row, param_ty);

    // Publish the generic return dependency by dense call-site identity. The
    // scalar expression pass pointer-jumps through this argument node, so two
    // instantiations of the same function never share token-keyed result state.
    uint return_slot = generic_slot_for_type_ref(
        fn_return_ref_tag[fn_i],
        fn_return_ref_payload[fn_i]);
    uint param_slot = param_direct_generic_slot_for_row(param_row);
    if (return_slot != INVALID && return_slot == param_slot)
    {
        uint ignored;
        InterlockedMin(call_generic_return_arg_node[call_node], arg_node, ignored);
    }

    // Transparent aliases retain their source-level named-instance ref for
    // diagnostics and interface projection, but their checked type is already
    // the substituted scalar. Alias arguments are substitution inputs, not
    // nominal children of the call parameter, so validate the scalar directly.
    if (param_ty != TY_UNKNOWN &&
        param_ty < TY_ARRAY_BASE &&
        !is_generic_type(param_ty))
    {
        uint arg_ty = expr_type_no_nested_call(arg_node);
        if (arg_ty != TY_UNKNOWN && !assignable(param_ty, arg_ty))
            record_error(arg_token, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
        return;
    }

    if (param_ty != TY_UNKNOWN &&
        !is_generic_type(param_ty) &&
        !is_symbolic_array_type(param_ty))
    {
        if (!check_concrete_instance_argument(callee_i, arg_node, param_row, param_ty))
            return;

        uint expected_instance;
        bool has_symbolic_instance_args = false;
        if (param_instance_ref_for_row(param_row, expected_instance) &&
            !concrete_leaf_instance_supported(expected_instance))
        {
            has_symbolic_instance_args = true;
        }

        if (!has_symbolic_instance_args)
        {
            if (param_ty >= TY_STRUCT_BASE && param_ty < TY_GENERIC_BASE)
                return;
            uint arg_ty = expr_type_no_nested_call(arg_node);
            if (arg_ty != TY_UNKNOWN && !assignable(param_ty, arg_ty))
                record_error(arg_token, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
            return;
        }
    }

    if (is_generic_type(param_ty))
    {
        uint direct_generic_token = param_direct_generic_token_for_row(param_row);
        uint direct_slot = param_direct_generic_slot_for_row(param_row);
        if (direct_slot != INVALID)
        {
            uint arg_ty = expr_type_no_nested_call(arg_node);
            if (valid_token(direct_generic_token))
            {
                claim_return_generic_token(
                    callee_i,
                    fn_i,
                    direct_generic_token,
                    arg_ty,
                    arg_token);
            }
            emit_generic_claim(row, callee_i, direct_slot, arg_ty);
            claim_generic_slot(
                callee_i,
                direct_slot,
                arg_ty,
                arg_token,
                param_ordinal);
        }

        uint array_slot = array_or_slice_generic_slot(param_ty);
        if (array_slot != INVALID)
        {
            uint arg_ty = array_or_slice_element_type_for_arg_node(arg_node);
            emit_generic_claim(row, callee_i, array_slot, arg_ty);
            claim_generic_slot(
                callee_i,
                array_slot,
                arg_ty,
                arg_token,
                param_ordinal);
        }
        else
        {
            uint slot = plain_generic_slot(param_ty);
            if (slot != INVALID)
                claim_generic_slot(
                    callee_i,
                    slot,
                    expr_type_no_nested_call(arg_node),
                    arg_token,
                    param_ordinal);
        }
    }

    uint array_ref_slot = param_array_or_slice_generic_slot_for_row(param_row);
    if (array_ref_slot != INVALID)
    {
        uint arg_ty = array_or_slice_element_type_for_arg_node(arg_node);
        uint array_generic_token = param_array_or_slice_generic_token_for_row(param_row);
        if (valid_token(array_generic_token))
            claim_return_generic_token(
                callee_i,
                fn_i,
                array_generic_token,
                arg_ty,
                arg_token);
        emit_generic_claim(row, callee_i, array_ref_slot, arg_ty);
        claim_generic_slot(
            callee_i,
            array_ref_slot,
            arg_ty,
            arg_token,
            param_ordinal);
    }

    uint const_len_slot = param_array_const_len_slot_for_row(param_row);
    if (const_len_slot != INVALID)
    {
        uint arg_len = literal_array_len_for_arg_node(arg_node);
        emit_const_claim(row, callee_i, const_len_slot, arg_len);
        claim_const_slot_len(
            callee_i,
            const_len_slot,
            arg_len,
            arg_token);
    }

    collect_instance_generic_arg(row, callee_i, arg_node, param_row, 0u, param_ordinal);
    collect_instance_generic_arg(row, callee_i, arg_node, param_row, 1u, param_ordinal);
    collect_instance_generic_arg(row, callee_i, arg_node, param_row, 2u, param_ordinal);
    collect_instance_generic_arg(row, callee_i, arg_node, param_row, 3u, param_ordinal);
    collect_instance_generic_arg(row, callee_i, arg_node, param_row, 4u, param_ordinal);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    collect_row_argument(linear_thread_id(dtid));
}
