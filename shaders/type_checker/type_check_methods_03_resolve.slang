// Final method-call result publication and argument validation.
//
// This pass consumes the sorted-table method resolution written at the method
// name token plus parser-owned member/call-argument records. It does not
// rediscover calls by scanning token neighborhoods or by matching
// parentheses/commas in token ranges.

import gpu_index;
import generated_parse_production_ids;
import hir_records;
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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_call_name_id;
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
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;

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

uint method_resolve_first_child_record(uint i)
{
    return first_child[i];
}

uint first_child_node(uint i)
{
    uint child = valid_node(i) ? method_resolve_first_child_record(i) : INVALID;
    return valid_node(child) ? child : INVALID;
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

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint prod_ty = scalar_type_for_literal_prod(node_kind[node]);
    if (prod_ty != TY_UNKNOWN)
        return prod_ty;

    uint token_i = hir_token_pos[node];
    if (token_i >= active_token_count())
        return TY_UNKNOWN;

    if (hir_kind[node] == HIR_NAME_EXPR)
    {
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

    if (hir_kind[node] == HIR_CALL_EXPR && token_i > 0u)
        return call_return_type[token_i - 1u];

    return TY_UNKNOWN;
}

uint expr_type_from_hir(uint expr_node)
{
    uint cur = expr_node;
    [loop]
    for (uint guard = 0u; guard < 32u && valid_node(cur); guard += 1u)
    {
        uint ty = direct_node_type(cur);
        if (ty != TY_UNKNOWN)
            return ty;
        cur = first_child_node(cur);
    }
    return TY_UNKNOWN;
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
    [loop]
    for (uint node = 0u; node < active_hir_node_count(); node += 1u)
    {
        uint packed = hir_call_arg_parent_call[node];
        if (hir_node_ordinal_node(packed) == call_node &&
            hir_node_ordinal_ordinal(packed) == ordinal)
            return node;
    }
    return INVALID;
}

uint receiver_token_for_member(uint member_node)
{
    return valid_node(member_node) ? hir_member_receiver_token[member_node] : INVALID;
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
        actual_args = PARAM_CACHE_STRIDE;
    [loop]
    for (uint arg_i = 0u; arg_i < actual_args && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_i = receiver_consumed ? arg_i + 1u : arg_i;
        if (param_i >= PARAM_CACHE_STRIDE)
            break;

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
    }

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

    uint ret_ty = call_return_type[fn_i];
    call_fn_index[method_i] = fn_i;
    call_return_type[method_i] = ret_ty;
    call_return_type_token[method_i] = call_return_type_token[fn_i];
    if (ret_ty != TY_UNKNOWN)
        visible_type[method_i] = ret_ty;
    if (call_return_type[receiver_i] != TY_UNKNOWN)
        call_return_type[receiver_i] = ret_ty;

    validate_method_args(method_i, fn_i, receiver_ty);
}

void reject_unresolved_marked_method_token(uint method_i)
{
    if (method_i >= active_token_count() || method_call_name_id[method_i] == INVALID)
        return;

    uint fn_i = call_fn_index[method_i];
    if (fn_i == INVALID || fn_i >= active_token_count())
        record_error(method_i, ERR_CALL_MISMATCH, method_call_name_id[method_i]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < active_token_count())
        reject_unresolved_marked_method_token(i);

    if (i >= active_hir_node_count() || hir_kind[i] != HIR_MEMBER_EXPR)
        return;

    resolve_method_member_node(i);
}
