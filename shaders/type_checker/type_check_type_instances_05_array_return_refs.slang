// HIR array-return projection.
//
// This pass consumes parser-owned return-statement records, visible-decl
// records, declaration type refs, and function return type refs. It publishes
// the array-return sentinel for `return values;` and bounded `return
// copy(values);` call results only when the returned declaration or
// declaration-backed call argument has the same bounded array instance as the
// enclosing function return type. It does not inspect token kinds, token
// spelling, source bytes, helper names, callee bodies, or expression
// punctuation.

import hir_records;
import status;
import tree_walk;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
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

static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;

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

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint parent_node(uint node)
{
    return valid_node(node) ? parent[node] : INVALID;
}

public struct ArrayReturnWalkGraph : ITreeWalkGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return parent_node(node);
    }
}

public struct ArrayReturnFnPredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return hir_kind[node] == HIR_FN;
    }
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_FORM);
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_slot(node, HIR_EXPR_RECORD_LEFT);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) || hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : hir_token_pos[node];
}

uint owning_function_node(uint node)
{
    uint fn_node;
    return find_self_or_ancestor<ArrayReturnWalkGraph, ArrayReturnFnPredicate>(
        node,
        128u,
        fn_node) ? fn_node : INVALID;
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
    uint fn_node = owning_function_node(return_node);
    if (!valid_node(fn_node))
        return INVALID;

    uint fn_token = hir_token_pos[fn_node];
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
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    uint token = hir_token_pos[callee_node];
    return valid_token(token) ? token : INVALID;
}

uint first_array_call_node(uint root)
{
    if (!valid_node(root))
        return INVALID;

    uint end = min(subtree_end[root], active_hir_node_count());
    if (end <= root)
        end = active_hir_node_count();
    [loop]
    for (uint node = root; node < end; node += 1u)
    {
        if (hir_kind[node] != HIR_CALL_EXPR)
            continue;
        uint callee_token = call_callee_token(node);
        if (valid_token(callee_token) && is_array_type(call_return_type[callee_token]))
            return node;
    }
    return INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node))
        return INVALID;

    uint end = min(subtree_end[call_node], active_hir_node_count());
    [loop]
    for (uint node = call_node + 1u; node < end; node += 1u)
    {
        uint packed = hir_call_arg_parent_call[node];
        if (hir_node_ordinal_node(packed) == call_node &&
            hir_node_ordinal_ordinal(packed) == ordinal)
            return node;
    }
    return INVALID;
}

uint returned_call_arg_array_instance(uint return_node)
{
    uint expr_node = hir_stmt_record[stmt_slot(return_node, 1u)];
    uint call_node = first_array_call_node(expr_node);
    if (!valid_node(call_node))
        return INVALID;

    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint arg_token = name_token_for_expr(arg_node);
    return declaration_array_instance(arg_token);
}

void publish_identifier_array_return(uint return_node)
{
    if (hir_kind[return_node] != HIR_RETURN_STMT ||
        hir_stmt_record[stmt_slot(return_node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[return_node];
    if (!valid_token(return_token))
        return;

    uint value_token = hir_stmt_record[stmt_slot(return_node, 3u)];
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
    if (hir_kind[return_node] != HIR_RETURN_STMT ||
        hir_stmt_record[stmt_slot(return_node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[return_node];
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
    if (!valid_node(node))
        return;

    publish_identifier_array_return(node);
    publish_call_array_return(node);
}
