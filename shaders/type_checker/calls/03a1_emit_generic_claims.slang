// Emit direct-call generic claims from compact per-argument claim spans.
//
// The argument collection pass marks how many generic relations each compact
// call-argument row can contribute. A prefix scan turns those counts into claim
// spans; this pass runs one thread per claim row and maps back to the owning
// argument row with a logarithmic search. Wide instance arguments therefore
// produce multiple sortable claims without one shader thread looping over every
// type argument.

import atomics;
import generated_parse_production_ids;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_param_row;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_scan_input;
StructuredBuffer<uint> call_generic_claim_prefix;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> call_generic_claim_callee;
RWStructuredBuffer<uint> call_generic_claim_slot;
RWStructuredBuffer<uint> call_generic_claim_type;
RWStructuredBuffer<uint> call_generic_claim_arg_row;
RWStructuredBuffer<uint> call_generic_claim_order;
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
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
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
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_GENERIC_CLAIM_CAPACITY = 0xffffff04u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint generic_claim_capacity()
{
    uint base = max(active_token_count(), active_hir_node_count());
    uint max_base = 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER;
    return base > max_base ? 0xffffffffu : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
}

uint active_claim_count()
{
    return min(call_generic_claim_count_out[0u], generic_claim_capacity());
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
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
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
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
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

uint scalar_type_for_literal_prod(uint prod)
{
    if (prod == PROD_INT)
        return TY_INT;
    if (prod == PROD_TRUE || prod == PROD_FALSE)
        return TY_BOOL;
    if (prod == PROD_FLOAT)
        return TY_FLOAT;
    if (prod == PROD_STRING)
        return TY_STRING;
    if (prod == PROD_CHAR)
        return TY_CHAR;
    return TY_UNKNOWN;
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
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint call_token = hir_token_pos[call_node];
    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return valid_token(call_token) ? call_token : INVALID;

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }

    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    uint callee_token = expr_value_token(callee_node);
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[callee_node];
    if (!valid_token(callee_token))
        callee_token = hir_token_pos[call_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint direct_node_type_no_nested_call(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = scalar_type_for_literal_prod(node_kind[node]);
    if (lit != TY_UNKNOWN)
        return lit;

    uint token = hir_token_pos[node];
    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint value_token = expr_value_token(node);
        if (valid_token(value_token))
            token = value_token;
        return visible_type_for_token(token);
    }

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        return visible_type_for_token(member_token);
    }

    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR)
    {
        uint head_node = hir_struct_lit_head_node[node];
        return valid_node(head_node) ? visible_type_for_token(hir_token_pos[head_node])
                                     : TY_UNKNOWN;
    }

    if (hir_kind[node] == HIR_INDEX_EXPR || hir_kind[node] == HIR_MATCH_EXPR)
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;

    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_token = callee_token_for_hir_call(node);
        if (!valid_token(callee_token))
            callee_token = hir_token_pos[node];
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
            token = hir_token_pos[node];
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
        form == HIR_EXPR_MOD ||
        form == HIR_EXPR_DIV ||
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

uint direct_name_expr_token(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node))
        return INVALID;
    if (expr_form(node) != HIR_EXPR_NAME && hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;
    uint token = expr_value_token(node);
    if (!valid_token(token))
        token = hir_token_pos[node];
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
    return valid_token(expected_decl) &&
           valid_token(actual_decl) &&
           expected_decl == actual_decl;
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
    if (!valid_node(actual_call_node) || hir_kind[actual_call_node] != HIR_CALL_EXPR)
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
    return valid_node(arg_node) ? hir_token_pos[arg_node] : callee_i;
}

uint call_arg_row_for_claim(uint claim_i)
{
    uint row_count = min(call_arg_row_count_out[0u], active_hir_node_count());
    uint lo = 0u;
    uint hi = row_count;
    [unroll]
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = call_generic_claim_prefix[mid];
        uint count = call_generic_claim_scan_input[mid];
        uint end = start + count;
        if (claim_i < start)
        {
            hi = mid;
        }
        else if (claim_i >= end)
        {
            lo = mid + 1u;
        }
        else
        {
            return mid;
        }
    }
    return INVALID;
}

void clear_generic_claim(uint claim_i)
{
    call_generic_claim_callee[claim_i] = INVALID;
    call_generic_claim_slot[claim_i] = INVALID;
    call_generic_claim_type[claim_i] = TY_UNKNOWN;
    call_generic_claim_arg_row[claim_i] = INVALID;
    call_generic_claim_order[claim_i] = claim_i;
}

void emit_generic_claim(uint claim_i, uint arg_row, uint callee_i, uint slot, uint arg_ty)
{
    if (!valid_token(callee_i) || slot == INVALID)
        return;

    call_generic_claim_callee[claim_i] = callee_i;
    call_generic_claim_slot[claim_i] = slot;
    call_generic_claim_type[claim_i] = arg_ty;
    call_generic_claim_arg_row[claim_i] = arg_row;
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

void emit_instance_generic_claim(
    uint claim_i,
    uint arg_row,
    uint callee_i,
    uint fn_i,
    uint arg_node,
    uint param_row,
    uint instance_arg_i)
{
    uint expected_instance;
    if (!param_instance_ref_for_row(param_row, expected_instance))
        return;

    uint expected_tag;
    uint expected_payload;
    if (!instance_arg_ref(expected_instance, instance_arg_i, expected_tag, expected_payload))
        return;

    uint arg_ty = actual_instance_or_call_return_arg_type(
        arg_node,
        expected_instance,
        instance_arg_i);

    if (expected_tag == TYPE_REF_SCALAR)
    {
        if (arg_ty != expected_payload)
            record_error(
                call_arg_error_token(arg_node, callee_i),
                ERR_ASSIGN_MISMATCH,
                expected_payload * 256u + arg_ty);
        return;
    }

    if (expected_tag != TYPE_REF_GENERIC_PARAM)
        return;

    uint slot = param_instance_generic_slot_for_row(param_row, instance_arg_i);
    if (slot == INVALID)
        return;

    uint generic_token = param_instance_generic_token_for_row(param_row, instance_arg_i);
    if (valid_token(generic_token))
        claim_return_generic_token(
            callee_i,
            fn_i,
            generic_token,
            arg_ty,
            call_arg_error_token(arg_node, callee_i));
    emit_generic_claim(claim_i, arg_row, callee_i, slot, arg_ty);
}

void emit_claim_for_relation(uint claim_i, uint arg_row, uint relation_i)
{
    uint call_node = call_arg_row_call_node[arg_row];
    uint arg_node = call_arg_row_node[arg_row];
    if (!valid_node(call_node) || !valid_node(arg_node))
        return;

    uint callee_i = callee_token_for_hir_call(call_node);
    if (!valid_token(callee_i) ||
        call_intrinsic_tag[callee_i] != INTRINSIC_NONE)
        return;

    uint fn_i = call_fn_index[callee_i];
    if (!valid_token(fn_i))
        return;

    uint param_row = arg_row < call_arg_row_count_out[0u] ? call_arg_param_row[arg_row] : INVALID;
    if (param_row == INVALID)
        return;

    uint param_ty = call_param_row_type[param_row];
    uint arg_token = call_arg_error_token(arg_node, callee_i);
    uint rel = relation_i;

    if (is_generic_type(param_ty))
    {
        uint direct_generic_token = param_direct_generic_token_for_row(param_row);
        if (valid_token(direct_generic_token))
        {
            if (rel == 0u)
            {
                uint arg_ty = expr_type_no_nested_call(arg_node);
                claim_return_generic_token(
                    callee_i,
                    fn_i,
                    direct_generic_token,
                    arg_ty,
                    arg_token);
                uint direct_slot = generic_slot_for_type_ref(
                    TYPE_REF_GENERIC_PARAM,
                    direct_generic_token);
                emit_generic_claim(claim_i, arg_row, callee_i, direct_slot, arg_ty);
                return;
            }
            rel -= 1u;
        }

        uint array_slot = array_or_slice_generic_slot(param_ty);
        if (array_slot != INVALID)
        {
            if (rel == 0u)
            {
                uint arg_ty = array_or_slice_element_type_for_arg_node(arg_node);
                emit_generic_claim(claim_i, arg_row, callee_i, array_slot, arg_ty);
                return;
            }
            rel -= 1u;
        }
    }

    uint array_ref_slot = param_array_or_slice_generic_slot_for_row(param_row);
    if (array_ref_slot != INVALID)
    {
        if (rel == 0u)
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
            emit_generic_claim(claim_i, arg_row, callee_i, array_ref_slot, arg_ty);
            return;
        }
        rel -= 1u;
    }

    emit_instance_generic_claim(
        claim_i,
        arg_row,
        callee_i,
        fn_i,
        arg_node,
        param_row,
        rel);
}

void emit_claim(uint claim_i)
{
    uint capacity = generic_claim_capacity();
    if (claim_i == capacity)
    {
        if (call_generic_claim_count_out[0u] <= capacity)
            return;

        uint arg_row = call_arg_row_for_claim(capacity);
        if (arg_row == INVALID)
        {
            record_error(0u, ERR_CALL_MISMATCH, CALL_MISMATCH_GENERIC_CLAIM_CAPACITY);
            return;
        }

        uint call_node = call_arg_row_call_node[arg_row];
        uint arg_node = call_arg_row_node[arg_row];
        uint callee_i = callee_token_for_hir_call(call_node);
        record_error(
            call_arg_error_token(arg_node, callee_i),
            ERR_CALL_MISMATCH,
            CALL_MISMATCH_GENERIC_CLAIM_CAPACITY);
        return;
    }

    if (claim_i >= active_claim_count())
        return;

    clear_generic_claim(claim_i);

    uint arg_row = call_arg_row_for_claim(claim_i);
    if (arg_row == INVALID)
        return;

    uint start = call_generic_claim_prefix[arg_row];
    uint count = call_generic_claim_scan_input[arg_row];
    if (claim_i < start || claim_i >= start + count)
        return;

    emit_claim_for_relation(claim_i, arg_row, claim_i - start);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    emit_claim(linear_thread_id(dtid));
}
