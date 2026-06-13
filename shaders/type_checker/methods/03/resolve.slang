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
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
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

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
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
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF = 0xffffff01u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC = 0xffffff02u;
static const uint CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE = 0xffffff03u;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;

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

bool valid_node(uint i)
{
    return i != INVALID && i < active_hir_node_count();
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
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

    uint token = hir_token_pos[callee_node];
    return valid_token(token) ? token : INVALID;
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
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

uint expr_type_from_hir(uint expr_node)
{
    if (!valid_node(expr_node))
        return TY_UNKNOWN;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count() || hir_kind[i] != HIR_MEMBER_EXPR)
        return;

    resolve_method_member_node(i);
}
