// Publish per-call array-argument facts from compact argument rows.
//
// Conditions consume this fact instead of scanning a fixed argument window.
// Each compact argument row does O(1) type attribution for its own expression
// and atomically marks the owning call when the argument is array-typed.

import atomics;
import hir_expr_semantics;

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
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_param_row;

RWStructuredBuffer<uint> call_has_array_arg;
RWStructuredBuffer<uint> call_result_instance;

static const uint INVALID = 0xffffffffu;

static const uint HIR_ARRAY_EXPR = 24u;
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
static const uint HIR_EXPR_INDEX = 28u;

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
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

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

uint expr_record_slot(uint node, uint slot)
{
    if (!valid_node(node)) return INVALID;
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
    return node;
}

uint value_token_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = expr_value_token(node);
    if (!valid_token(token))
        token = compact_hir_core[node].token_start;
    return valid_token(token) ? token : INVALID;
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

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = hir_scalar_type_for_expr_form(expr_form(node));
    if (lit != TY_UNKNOWN)
        return lit;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return TY_UNKNOWN;

    if (compact_hir_core[node].kind == HIR_NAME_EXPR)
        return visible_type_for_token(value_token_for_node(node));

    if (compact_hir_core[node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[node].c;
        return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
    }

    if (compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR)
        return visible_type_for_token(compact_hir_core[node].token_start);

    if (compact_hir_core[node].kind == HIR_ARRAY_EXPR ||
        compact_hir_core[node].kind == HIR_INDEX_EXPR ||
        compact_hir_core[node].kind == HIR_MATCH_EXPR)
        return call_return_type[token];

    if (compact_hir_core[node].kind == HIR_CALL_EXPR)
    {
        uint call_ty = call_return_type[token];
        if (call_ty != TY_UNKNOWN)
            return call_ty;

        uint callee_node = compact_hir_payload[node].a;
        if (!valid_node(callee_node))
            return TY_UNKNOWN;
        if (compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
        {
            uint member_token = compact_hir_payload[callee_node].c;
            return valid_token(member_token) ? visible_type_for_token(member_token) : TY_UNKNOWN;
        }
        uint callee_token = value_token_for_node(callee_node);
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

uint direct_expr_record_type(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

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
        return valid_token(token) ? visible_type_for_token(token) : TY_UNKNOWN;
    }
    if (form == HIR_EXPR_INDEX)
    {
        uint token = compact_hir_core[node].token_start;
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;
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
        uint left_ty = direct_node_type(resolve_expr(expr_record_slot(node, HIR_EXPR_RECORD_LEFT)));
        uint right_ty = direct_node_type(resolve_expr(expr_record_slot(node, HIR_EXPR_RECORD_RIGHT)));
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

bool expression_result_node(uint node)
{
    if (!valid_node(node))
        return false;
    return compact_hir_core[node].kind == HIR_CALL_EXPR ||
           compact_hir_core[node].kind == HIR_MEMBER_EXPR ||
           compact_hir_core[node].kind == HIR_INDEX_EXPR ||
           compact_hir_core[node].kind == HIR_MATCH_EXPR ||
           compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR;
}

uint first_value_type_from_node(uint root)
{
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(root);
    if (record_ty != TY_UNKNOWN)
        return record_ty;

    uint resolved = resolve_expr(root);
    if (expression_result_node(resolved))
        return direct_node_type(resolved);

    return direct_node_type(root);
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         expr_form(node) != HIR_EXPR_NAME))
        return INVALID;

    uint token = expr_value_token(node);
    return valid_token(token) ? token : compact_hir_core[node].token_start;
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

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    return tag == TYPE_REF_INSTANCE &&
           valid_token(payload) &&
           type_instance_kind[payload] == TYPE_INSTANCE_ARRAY
               ? payload
               : INVALID;
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
    return tag == TYPE_REF_INSTANCE && valid_token(payload);
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
    if (!valid_token(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return false;
    if (type_instance_len_kind[instance] != TYPE_LEN_LITERAL)
        return false;
    return concrete_array_elem_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

bool same_bounded_array_instance(uint lhs, uint rhs)
{
    if (!valid_token(lhs) || !valid_token(rhs))
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

void mark_array_return_arg_instance(uint call_node, uint arg_node, uint param_row)
{
    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;

    uint declared_instance = array_instance_from_callee_return(callee_token);
    if (declared_instance == INVALID)
        return;

    uint expected_arg_instance = array_instance_from_call_param_row(param_row);
    if (!same_bounded_array_instance(declared_instance, expected_arg_instance))
        return;

    uint actual_instance = array_instance_from_name_token(name_token_for_expr(arg_node));
    if (!concrete_bounded_array_instance(actual_instance))
        return;
    atomic_u32_min(call_result_instance, call_node, actual_instance);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint row_count = min(call_arg_row_count_out[0u], active_hir_node_count());
    if (row >= row_count)
        return;

    uint arg_node = call_arg_row_node[row];
    uint call_node = call_arg_row_call_node[row];
    if (!valid_node(arg_node) || !valid_node(call_node))
        return;

    if (is_array_type(first_value_type_from_node(arg_node)))
    {
        atomic_u32_max(call_has_array_arg, call_node, 1u);
        mark_array_return_arg_instance(call_node, arg_node, call_arg_param_row[row]);
    }
}
