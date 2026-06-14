// Final method-call result publication and argument validation.
//
// This pass consumes the sorted-table method resolution written at the method
// name token plus parser-owned member/call-argument and expression-result
// records. It does not rediscover calls by scanning token neighborhoods,
// matching parentheses/commas in token ranges, or walking child lists.

import gpu_index;
import generated_parse_production_ids;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_node;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> hir_method_signature_flags;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> module_value_path_call_open;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF = 0xffffff01u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC = 0xffffff02u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE = 0xffffff03u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

static const uint HIR_TYPE = 5u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_VALUE_TOKEN = 3u;

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

static const uint METHOD_RECEIVER_NONE = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint MAX_PATH_SEGMENTS = 9u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_COLON = 38u;
static const uint TK_PATH_COLON = 114u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_path(uint i)
{
    return i != INVALID && i < active_path_count();
}

uint token_kind(uint token_i)
{
    return token_i < active_token_count() ? token_words[token_i].kind : 0u;
}

bool type_arg_open(uint kind)
{
    return kind == TK_LT || kind == TK_PATH_TYPE_ARG_LT || kind == TK_TYPE_ARG_LT;
}

bool type_arg_close(uint kind)
{
    return kind == TK_GT || kind == TK_PATH_TYPE_ARG_GT || kind == TK_TYPE_ARG_GT;
}

bool path_colon(uint kind)
{
    return kind == TK_COLON || kind == TK_PATH_COLON;
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
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

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
        return visible_type[payload];
    return TY_UNKNOWN;
}

uint receiver_arg_ref_index(uint method_i, uint slot)
{
    if (method_i >= active_token_count() || slot >= PARAM_CACHE_STRIDE)
        return INVALID;

    uint receiver_tag = method_call_receiver_ref_tag[method_i];
    uint receiver_payload = method_call_receiver_ref_payload[method_i];
    if (receiver_tag != TYPE_REF_INSTANCE || !valid_token(receiver_payload))
        return INVALID;

    uint arg_count = type_instance_arg_count[receiver_payload];
    uint arg_start = type_instance_arg_start[receiver_payload];
    if (slot >= arg_count || arg_start == INVALID)
        return INVALID;

    uint arg_i = arg_start + slot;
    return arg_i < active_token_count() ? arg_i : INVALID;
}

uint receiver_decl_generic_slot_at(
    uint arg_start,
    uint arg_count,
    uint generic_token,
    uint slot)
{
    if (slot >= arg_count)
        return INVALID;

    uint arg_i = arg_start + slot;
    if (arg_i >= active_token_count())
        return INVALID;

    if (type_instance_arg_ref_tag[arg_i] == TYPE_REF_GENERIC_PARAM &&
        type_instance_arg_ref_payload[arg_i] == generic_token)
        return slot;
    return INVALID;
}

uint receiver_decl_generic_slot(uint fn_i, uint generic_token)
{
    if (fn_i >= active_token_count() || !valid_token(generic_token))
        return INVALID;

    uint receiver_tag = method_decl_receiver_ref_tag[fn_i];
    uint receiver_payload = method_decl_receiver_ref_payload[fn_i];
    if (receiver_tag != TYPE_REF_INSTANCE || !valid_token(receiver_payload))
        return INVALID;

    uint arg_count = type_instance_arg_count[receiver_payload];
    uint arg_start = type_instance_arg_start[receiver_payload];
    if (arg_start == INVALID)
        return INVALID;

    uint slot = receiver_decl_generic_slot_at(arg_start, arg_count, generic_token, 0u);
    if (slot != INVALID)
        return slot;
    slot = receiver_decl_generic_slot_at(arg_start, arg_count, generic_token, 1u);
    if (slot != INVALID)
        return slot;
    slot = receiver_decl_generic_slot_at(arg_start, arg_count, generic_token, 2u);
    if (slot != INVALID)
        return slot;
    slot = receiver_decl_generic_slot_at(arg_start, arg_count, generic_token, 3u);
    if (slot != INVALID)
        return slot;

    return INVALID;
}

uint substituted_method_return_type(uint method_i, uint fn_i, uint fallback_ty)
{
    if (fn_i >= active_token_count())
        return fallback_ty;

    uint ret_tag = fn_return_ref_tag[fn_i];
    uint ret_payload = fn_return_ref_payload[fn_i];
    if (ret_tag != TYPE_REF_GENERIC_PARAM || !valid_token(ret_payload))
        return fallback_ty;

    uint slot = receiver_decl_generic_slot(fn_i, ret_payload);
    uint arg_i = receiver_arg_ref_index(method_i, slot);
    if (arg_i == INVALID)
        return fallback_ty;

    uint ty = type_code_for_ref(
        type_instance_arg_ref_tag[arg_i],
        type_instance_arg_ref_payload[arg_i]);
    return ty == TY_UNKNOWN ? fallback_ty : ty;
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
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_VALUE_TOKEN) : INVALID;
}

uint scalar_type_for_expr_form(uint form)
{
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    return TY_UNKNOWN;
}

uint operator_result_type_for_expr_form(uint form)
{
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

uint associated_callee_method_token_for_call(uint call_node);

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }

    uint associated_method = associated_callee_method_token_for_call(call_node);
    if (valid_token(associated_method))
        return associated_method;

    uint token = hir_token_pos[callee_node];
    return valid_token(token) ? token : INVALID;
}

uint path_id_for_callee_node(uint callee_node)
{
    if (!valid_node(callee_node))
        return INVALID;

    if (hir_kind[callee_node] == HIR_PATH_EXPR || hir_kind[callee_node] == HIR_TYPE)
    {
        uint path_i = path_id_by_owner_hir[callee_node];
        return valid_path(path_i) ? path_i : INVALID;
    }

    if (hir_kind[callee_node] == HIR_NAME_EXPR)
    {
        uint child = first_child[callee_node];
        if (valid_node(child) && (hir_kind[child] == HIR_PATH_EXPR || hir_kind[child] == HIR_TYPE))
        {
            uint path_i = path_id_by_owner_hir[child];
            return valid_path(path_i) ? path_i : INVALID;
        }
    }

    return INVALID;
}

uint path_leaf_token(uint path_i)
{
    uint count = valid_path(path_i) ? min(path_segment_count[path_i], MAX_PATH_SEGMENTS) : 0u;
    if (count == 0u)
        return INVALID;
    uint slot = path_segment_base[path_i] + count - 1u;
    return slot < active_token_count() * MAX_PATH_SEGMENTS ? path_segment_token[slot] : INVALID;
}

uint associated_method_token_after_receiver(uint receiver_token)
{
    uint cursor = receiver_token + 1u;
    if (valid_token(cursor) && type_arg_open(token_kind(cursor)))
    {
        cursor += 1u;
        uint depth = 0u;
        [loop]
        for (uint guard = 0u; guard < 64u && valid_token(cursor); guard += 1u)
        {
            uint kind = token_kind(cursor);
            if (type_arg_open(kind))
                depth += 1u;
            else if (type_arg_close(kind))
            {
                if (depth == 0u)
                {
                    cursor += 1u;
                    break;
                }
                depth -= 1u;
            }
            cursor += 1u;
        }
    }

    if (valid_token(cursor + 2u) &&
        path_colon(token_kind(cursor)) &&
        path_colon(token_kind(cursor + 1u)))
        return cursor + 2u;

    return receiver_token;
}

uint associated_method_token_for_path(uint path_i)
{
    return associated_method_token_after_receiver(path_leaf_token(path_i));
}

uint fallback_associated_path_for_callee_token(uint callee_token)
{
    if (!valid_token(callee_token))
        return INVALID;

    uint count = active_path_count();
    [loop]
    for (uint path_i = 0u; path_i < count; path_i += 1u)
    {
        uint owner_token = path_owner_token[path_i];
        uint receiver_token = path_leaf_token(path_i);
        uint method_token = associated_method_token_for_path(path_i);
        if (valid_token(method_token) &&
            (callee_token == owner_token || callee_token == method_token))
            return path_i;
    }
    return INVALID;
}

uint fallback_associated_path_for_call_open(uint call_open)
{
    if (!valid_token(call_open))
        return INVALID;

    uint count = active_path_count();
    [loop]
    for (uint path_i = 0u; path_i < count; path_i += 1u)
    {
        uint method_token = associated_method_token_for_path(path_i);
        if (valid_token(method_token) && method_token + 1u == call_open)
            return path_i;
    }
    return INVALID;
}

uint associated_owner_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return INVALID;

    uint path_i = path_id_for_callee_node(callee_node);
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    uint call_open = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    if (!valid_path(path_i) ||
        associated_method_token_for_path(path_i) == path_owner_token[path_i])
    {
        uint fallback_path = fallback_associated_path_for_callee_token(callee_token);
        if (!valid_path(fallback_path))
            fallback_path = fallback_associated_path_for_call_open(call_open);
        if (valid_path(fallback_path))
            path_i = fallback_path;
    }
    return valid_path(path_i) ? path_owner_token[path_i] : INVALID;
}

uint associated_method_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return INVALID;

    uint path_i = path_id_for_callee_node(callee_node);
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    uint call_open = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    uint method_token = valid_path(path_i) ? associated_method_token_for_path(path_i) : INVALID;
    if (!valid_path(path_i) || method_token == path_owner_token[path_i])
    {
        uint fallback_path = fallback_associated_path_for_callee_token(callee_token);
        if (!valid_path(fallback_path))
            fallback_path = fallback_associated_path_for_call_open(call_open);
        if (valid_path(fallback_path))
        {
            path_i = fallback_path;
            method_token = associated_method_token_for_path(path_i);
        }
        if (!valid_path(path_i) && valid_token(callee_token))
            return callee_token;
    }
    return valid_path(path_i) ? method_token : INVALID;
}

uint associated_callee_method_token_for_call(uint call_node)
{
    uint callee_node = valid_node(call_node) ? hir_call_callee_node[call_node] : INVALID;
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return INVALID;

    uint path_i = path_id_for_callee_node(callee_node);
    uint callee_token = valid_node(callee_node) ? hir_token_pos[callee_node] : INVALID;
    uint call_open = valid_node(call_node) ? hir_token_pos[call_node] : INVALID;
    if (!valid_path(path_i))
    {
        uint fallback_path = fallback_associated_path_for_callee_token(callee_token);
        if (!valid_path(fallback_path))
            fallback_path = fallback_associated_path_for_call_open(call_open);
        if (valid_path(fallback_path))
            path_i = fallback_path;
    }
    if (!valid_path(path_i))
        return INVALID;

    uint method_token = associated_method_token_after_receiver(path_leaf_token(path_i));
    return valid_token(method_token) ? method_token : INVALID;
}

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint prod_ty = scalar_type_for_literal_prod(node_kind[node]);
    if (prod_ty != TY_UNKNOWN)
        return prod_ty;

    uint form = expr_form(node);
    uint expr_ty = scalar_type_for_expr_form(form);
    if (expr_ty != TY_UNKNOWN)
        return expr_ty;
    expr_ty = operator_result_type_for_expr_form(form);
    if (expr_ty != TY_UNKNOWN)
        return expr_ty;

    uint token_i = hir_token_pos[node];
    if (token_i >= active_token_count())
        return TY_UNKNOWN;

    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint value_token = expr_value_token(node);
        if (valid_token(value_token))
            token_i = value_token;
        uint visible_ty = visible_type[token_i];
        if (visible_ty != TY_UNKNOWN)
            return visible_ty;
        return call_return_type[token_i];
    }

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_i = hir_member_name_token[node];
        if (member_i >= active_token_count())
            return TY_UNKNOWN;
        uint member_ty = visible_type[member_i];
        if (member_ty != TY_UNKNOWN)
            return member_ty;
        return call_return_type[member_i];
    }

    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_token = call_callee_token(node);
        if (!valid_token(callee_token))
            callee_token = hir_token_pos[node];
        uint call_ty = valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
        if (call_ty != TY_UNKNOWN && call_ty != TY_VOID)
            return call_ty;

        uint associated_method = associated_callee_method_token_for_call(node);
        uint fn_i = valid_token(associated_method) ? call_fn_index[associated_method] : INVALID;
        if (valid_token(fn_i))
        {
            uint ret_ty = substituted_method_return_type(
                associated_method,
                fn_i,
                call_return_type[fn_i]);
            if (ret_ty != TY_UNKNOWN)
                return ret_ty;
        }

        return call_ty;
    }

    return TY_UNKNOWN;
}

uint expr_type_from_hir(uint expr_node)
{
    if (!valid_node(expr_node))
        return TY_UNKNOWN;

    uint direct_ty = direct_node_type(expr_node);
    if (direct_ty != TY_UNKNOWN)
        return direct_ty;

    uint result = hir_expr_result_root_node[expr_node];
    if (!valid_node(result))
        return TY_UNKNOWN;

    return direct_node_type(result);
}

bool method_has_self_receiver(uint fn_i)
{
    uint mode = fn_i < active_token_count() ? method_decl_receiver_mode[fn_i] : METHOD_RECEIVER_NONE;
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

bool method_explicit_receiver_consumes_param(uint fn_i, uint receiver_ty)
{
    uint mode = fn_i < active_token_count() ? method_decl_receiver_mode[fn_i] : METHOD_RECEIVER_NONE;
    if (mode != METHOD_RECEIVER_EXPLICIT)
        return false;
    if (call_param_count[fn_i] == 0u)
        return false;
    uint first_ty = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        0u,
        TY_UNKNOWN);
    return first_ty == receiver_ty;
}

uint call_node_for_method_token(uint method_i)
{
    if (method_i >= active_token_count())
        return INVALID;
    return call_arg_record[method_i].z;
}

uint call_arg_count_for_method_token(uint method_i)
{
    if (method_i >= active_token_count())
        return 0u;
    return call_arg_record[method_i].w;
}

uint call_arg_node_for_method_token(uint method_i, uint ordinal)
{
    if (method_i >= active_token_count() || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    uint call_node = call_arg_record[method_i].z;
    if (!valid_node(call_node))
        return INVALID;
    return call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal];
}

uint call_arg_count_for_call_node(uint method_i, uint call_node)
{
    uint record_count = valid_token(method_i) ? call_arg_record[method_i].w : 0u;
    if (!valid_node(call_node))
        return record_count;
    return max(record_count, hir_call_arg_count[call_node]);
}

uint call_arg_node_for_call_node(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;
    return call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal];
}

uint receiver_token_for_member(uint member_node)
{
    return valid_node(member_node) ? hir_member_receiver_token[member_node] : INVALID;
}

bool validate_method_arg_slot(
    uint method_i,
    uint fn_i,
    bool receiver_consumed,
    uint actual_args,
    uint arg_i)
{
    if (arg_i >= actual_args)
        return true;

    uint param_i = receiver_consumed ? arg_i + 1u : arg_i;
    if (param_i >= PARAM_CACHE_STRIDE)
        return true;

    uint expr_node = call_arg_node_for_method_token(method_i, arg_i);
    uint dst = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        param_i,
        TY_UNKNOWN);
    uint src = expr_type_from_hir(expr_node);
    uint arg_token = valid_node(expr_node) ? hir_token_pos[expr_node] : method_i;
    if (!assignable(dst, src))
    {
        record_error(arg_token, ERR_ASSIGN_MISMATCH, dst * 256u + src);
        return false;
    }
    return true;
}

bool validate_method_args(uint method_i, uint fn_i, uint receiver_ty)
{
    uint param_count = call_param_count[fn_i];
    bool has_self_receiver = method_has_self_receiver(fn_i);
    bool consumes_receiver = method_explicit_receiver_consumes_param(fn_i, receiver_ty);
    if (!has_self_receiver && !consumes_receiver)
    {
        record_error(method_i, ERR_CALL_MISMATCH, receiver_ty);
        return false;
    }

    bool receiver_consumed = has_self_receiver || consumes_receiver;
    uint expected_args = receiver_consumed && param_count > 0u ? param_count - 1u : param_count;
    uint actual_args = call_arg_count_for_method_token(method_i);
    if (actual_args > PARAM_CACHE_STRIDE)
    {
        record_error(
            method_i,
            ERR_CALL_MISMATCH,
            expected_args * 256u + min(actual_args, 255u));
        return false;
    }
    if (!validate_method_arg_slot(method_i, fn_i, receiver_consumed, actual_args, 0u))
        return false;
    if (!validate_method_arg_slot(method_i, fn_i, receiver_consumed, actual_args, 1u))
        return false;
    if (!validate_method_arg_slot(method_i, fn_i, receiver_consumed, actual_args, 2u))
        return false;
    if (!validate_method_arg_slot(method_i, fn_i, receiver_consumed, actual_args, 3u))
        return false;

    if (actual_args != expected_args)
    {
        record_error(method_i, ERR_CALL_MISMATCH, expected_args * 256u + actual_args);
        return false;
    }
    return true;
}

bool validate_associated_arg_slot(
    uint method_i,
    uint fn_i,
    uint call_node,
    uint actual_args,
    uint arg_i)
{
    if (arg_i >= actual_args)
        return true;
    if (arg_i >= PARAM_CACHE_STRIDE)
        return true;

    uint expr_node = call_arg_node_for_call_node(call_node, arg_i);
    uint dst = row_major_load<uint>(
        call_param_type,
        fn_i,
        PARAM_CACHE_STRIDE,
        arg_i,
        TY_UNKNOWN);
    uint src = expr_type_from_hir(expr_node);
    uint arg_token = valid_node(expr_node) ? hir_token_pos[expr_node] : method_i;
    if (!assignable(dst, src))
    {
        record_error(arg_token, ERR_ASSIGN_MISMATCH, dst * 256u + src);
        return false;
    }
    return true;
}

bool validate_associated_args(uint method_i, uint fn_i, uint call_node)
{
    uint receiver_mode = method_decl_receiver_mode[fn_i];
    if (receiver_mode == METHOD_RECEIVER_SELF || receiver_mode == METHOD_RECEIVER_REF_SELF)
    {
        record_error(method_i, ERR_CALL_MISMATCH, receiver_mode);
        return false;
    }

    uint expected_args = call_param_count[fn_i];
    uint actual_args = call_arg_count_for_call_node(method_i, call_node);
    if (actual_args > PARAM_CACHE_STRIDE)
    {
        record_error(
            method_i,
            ERR_CALL_MISMATCH,
            expected_args * 256u + min(actual_args, 255u));
        return false;
    }
    if (!validate_associated_arg_slot(method_i, fn_i, call_node, actual_args, 0u))
        return false;
    if (!validate_associated_arg_slot(method_i, fn_i, call_node, actual_args, 1u))
        return false;
    if (!validate_associated_arg_slot(method_i, fn_i, call_node, actual_args, 2u))
        return false;
    if (!validate_associated_arg_slot(method_i, fn_i, call_node, actual_args, 3u))
        return false;

    if (actual_args != expected_args)
    {
        record_error(method_i, ERR_CALL_MISMATCH, expected_args * 256u + actual_args);
        return false;
    }
    return true;
}

void resolve_method_member_node(uint member_node)
{
    uint method_i = valid_node(member_node) ? hir_member_name_token[member_node] : INVALID;
    if (method_i >= active_token_count())
        return;
    if (method_call_name_id[method_i] == INVALID)
        return;

    uint call_node = call_node_for_method_token(method_i);
    if (call_node == INVALID)
        return;

    uint fn_i = call_fn_index[method_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
    {
        record_error(method_i, ERR_CALL_MISMATCH, method_call_name_id[method_i]);
        return;
    }

    uint receiver_i = receiver_token_for_member(member_node);
    if (receiver_i == INVALID || receiver_i >= active_token_count())
        return;
    uint receiver_ty = visible_type[receiver_i];
    if (receiver_ty == TY_UNKNOWN)
        receiver_ty = call_return_type[receiver_i];

    uint signature_flags = valid_node(fn_i) ? hir_method_signature_flags[fn_i] : 0u;
    if ((signature_flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC);
        return;
    }
    if ((signature_flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE);
        return;
    }

    uint ret_ty = substituted_method_return_type(method_i, fn_i, call_return_type[fn_i]);
    if ((ret_ty == TY_UNKNOWN && fn_return_ref_tag[fn_i] != TYPE_REF_INVALID) ||
        is_generic_type(ret_ty))
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF);
        return;
    }
    call_fn_index[method_i] = fn_i;
    call_return_type[method_i] = ret_ty;
    call_return_type_token[method_i] = call_return_type_token[fn_i];
    if (ret_ty != TY_UNKNOWN)
        visible_type[method_i] = ret_ty;
    if (call_return_type[receiver_i] != TY_UNKNOWN)
        call_return_type[receiver_i] = ret_ty;

    validate_method_args(method_i, fn_i, receiver_ty);
}

void publish_associated_call_result(
    uint method_i,
    uint owner_token,
    uint call_open,
    uint fn_i,
    uint ret_ty)
{
    call_fn_index[method_i] = fn_i;
    call_return_type[method_i] = ret_ty;
    call_return_type_token[method_i] = call_return_type_token[fn_i];
    if (ret_ty != TY_UNKNOWN)
        visible_type[method_i] = ret_ty;
    module_value_path_status[method_i] = PATH_RESOLVE_STATUS_INVALID;

    if (valid_token(owner_token))
    {
        call_fn_index[owner_token] = fn_i;
        call_return_type[owner_token] = ret_ty;
        call_return_type_token[owner_token] = call_return_type_token[fn_i];
        if (ret_ty != TY_UNKNOWN)
            visible_type[owner_token] = ret_ty;
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_INVALID;
    }

    if (valid_token(call_open))
    {
        call_fn_index[call_open] = fn_i;
        call_return_type[call_open] = ret_ty;
        call_return_type_token[call_open] = call_return_type_token[fn_i];
        if (ret_ty != TY_UNKNOWN)
            visible_type[call_open] = ret_ty;
    }
}

void resolve_associated_call_node(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return;

    uint method_i = associated_method_token_for_call(call_node);
    if (!valid_token(method_i))
        return;
    if (method_call_name_id[method_i] == INVALID)
        return;

    uint fn_i = call_fn_index[method_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
    {
        record_error(method_i, ERR_CALL_MISMATCH, method_call_name_id[method_i]);
        return;
    }

    uint signature_flags = valid_node(fn_i) ? hir_method_signature_flags[fn_i] : 0u;
    if ((signature_flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC);
        return;
    }
    if ((signature_flags & METHOD_SIGNATURE_HAS_WHERE) != 0u)
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE);
        return;
    }

    uint ret_ty = substituted_method_return_type(method_i, fn_i, call_return_type[fn_i]);
    if ((ret_ty == TY_UNKNOWN && fn_return_ref_tag[fn_i] != TYPE_REF_INVALID) ||
        is_generic_type(ret_ty))
    {
        record_error(method_i, ERR_CALL_MISMATCH, CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF);
        return;
    }

    if (!validate_associated_args(method_i, fn_i, call_node))
        return;

    uint owner_token = associated_owner_token_for_call(call_node);
    uint call_open = hir_token_pos[call_node];
    publish_associated_call_result(method_i, owner_token, call_open, fn_i, ret_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    if (hir_kind[i] == HIR_MEMBER_EXPR)
    {
        resolve_method_member_node(i);
        return;
    }

    if (hir_kind[i] == HIR_CALL_EXPR)
        resolve_associated_call_node(i);
}
