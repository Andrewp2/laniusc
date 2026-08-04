// HIR array-return projection.
//
// This pass consumes compact return statements and call arguments, visible-decl records,
// declaration type refs,
// and function return type refs. It publishes the array-return sentinel for `return values;` and
// bounded one-argument `return copy(values);` call results only when the returned declaration or
// declaration-backed call argument has the same bounded array instance as the
// enclosing function return type. It does not inspect token kinds, token
// spelling, source bytes, helper names, callee bodies, or expression
// punctuation.

import hir_records;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;


StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;
static const uint ERR_ASSIGN_MISMATCH = 3u;

static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;

static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint enclosing_function_decl_token(uint token)
{
    uint encoded_fn = valid_token(token) ? enclosing_fn[token] : 0u;
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (fn_node == INVALID || fn_node >= count)
        return INVALID;
    uint fn_token = compact_hir_payload[fn_node].b;
    return valid_token(fn_token) ? fn_token : INVALID;
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

HirPayload stmt_payload(uint node)
{
    HirPayload payload;
    payload.a = 0u;
    payload.b = INVALID;
    payload.c = INVALID;
    payload.d = INVALID;
    return node < active_compact_hir_count() ? compact_hir_payload[node] : payload;
}

uint name_token_for_expr(uint node)
{
    if (node >= active_compact_hir_count() || compact_hir_core[node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    uint len_kind = type_instance_len_kind[payload];
    if (len_kind != TYPE_LEN_LITERAL && len_kind != TYPE_LEN_CONST_PARAM)
        return INVALID;
    return payload;
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

bool same_bounded_array_instance(uint lhs, uint rhs)
{
    lhs = valid_token(lhs) ? lhs : INVALID;
    rhs = valid_token(rhs) ? rhs : INVALID;
    if (lhs == INVALID || rhs == INVALID)
        return false;
    if (type_instance_kind[lhs] != TYPE_INSTANCE_ARRAY ||
        type_instance_kind[rhs] != TYPE_INSTANCE_ARRAY)
        return false;
    if (!same_array_len(lhs, rhs))
        return false;
    return same_type_ref(
        type_instance_elem_ref_tag[lhs],
        type_instance_elem_ref_payload[lhs],
        type_instance_elem_ref_tag[rhs],
        type_instance_elem_ref_payload[rhs]);
}

uint function_return_array_instance(uint return_node)
{
    uint return_token = return_node < active_compact_hir_count()
        ? compact_hir_core[return_node].token_start
        : INVALID;
    if (!valid_token(return_token))
        return INVALID;

    uint fn_token = enclosing_function_decl_token(return_token);
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint declaration_array_instance(uint value_token)
{
    if (!valid_token(value_token))
        return INVALID;

    uint decl_token = visible_decl[value_token];
    if (!valid_token(decl_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl_token],
        decl_type_ref_payload[decl_token]);
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint call_callee_token(uint call_node)
{
    if (call_node >= active_compact_hir_count() || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_hir = compact_hir_payload[call_node].a;
    if (callee_hir >= active_compact_hir_count())
        return INVALID;

    HirCore callee = compact_hir_core[callee_hir];
    uint token = callee.kind == 21u
        ? compact_hir_payload[callee_hir].c
        : callee.token_start;
    return valid_token(token) ? token : INVALID;
}

uint call_argument_count(uint call_node)
{
    if (call_node >= active_compact_hir_count() || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return 0u;
    return compact_hir_payload[call_node].c;
}

uint direct_array_return_call_node(uint return_node)
{
    uint call_node = stmt_payload(return_node).b;
    if (call_node >= active_compact_hir_count() || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    if (call_argument_count(call_node) != 1u)
        return INVALID;

    uint callee_token = call_callee_token(call_node);
    return valid_token(callee_token) && is_array_type(call_return_type[callee_token])
               ? call_node
               : INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (call_node >= active_compact_hir_count())
        return INVALID;

    HirPayload call = compact_hir_payload[call_node];
    uint start = call.b;
    uint count = call.c;
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    uint active_args = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    if (row >= active_args)
        return INVALID;
    HirCallArg arg = compact_call_args[row];
    return arg.call == call_node && arg.ordinal == ordinal ? arg.value : INVALID;
}

uint returned_call_arg_array_instance(uint return_node)
{
    uint call_node = direct_array_return_call_node(return_node);
    if (call_node >= active_compact_hir_count())
        return INVALID;

    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint arg_token = name_token_for_expr(arg_node);
    return declaration_array_instance(arg_token);
}

void publish_identifier_array_return(uint return_node)
{
    HirPayload stmt = stmt_payload(return_node);
    if (return_node >= active_compact_hir_count() ||
        compact_hir_core[return_node].kind != HIR_RETURN_STMT ||
        stmt.a != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = compact_hir_core[return_node].token_start;
    if (!valid_token(return_token))
        return;

    uint value_token = stmt.d;
    uint src_instance = declaration_array_instance(value_token);
    if (src_instance == INVALID)
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (same_bounded_array_instance(dst_instance, src_instance))
        call_return_type[return_token] = ARRAY_RETURN_OK;
    else if (dst_instance != INVALID)
        record_min_token_error(status, return_token, ERR_ASSIGN_MISMATCH, 0u);
}

void publish_call_array_return(uint return_node)
{
    if (return_node >= active_compact_hir_count() ||
        compact_hir_core[return_node].kind != HIR_RETURN_STMT ||
        stmt_payload(return_node).a != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = compact_hir_core[return_node].token_start;
    if (!valid_token(return_token))
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (dst_instance == INVALID)
        return;

    uint src_instance = returned_call_arg_array_instance(return_node);
    if (same_bounded_array_instance(dst_instance, src_instance))
    {
        call_return_type[return_token] = ARRAY_RETURN_OK;
        return;
    }

    if (src_instance != INVALID)
        record_min_token_error(status, return_token, ERR_ASSIGN_MISMATCH, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_compact_hir_count())
        return;

    publish_identifier_array_return(node);
    publish_call_array_return(node);
}
