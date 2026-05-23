// HIR-record array call-result validation.
//
// This pass runs after bounded generic array call inference. It keeps
// array-valued call results length-aware by comparing the annotated destination
// declaration's array instance with either the callee's declared return array
// instance or the declaration-backed actual array argument instance. It consumes
// HIR statement/call records and type-instance refs; it does not inspect source
// bytes, token spelling, helper names, or callee function bodies.

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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
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

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;

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

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
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
    return valid_token(name_token) ? array_instance_from_decl_token(visible_decl[name_token])
                                   : INVALID;
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

void validate_array_call_let(uint node)
{
    if (!valid_node(node) ||
        hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_LET)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    uint expected_instance = array_instance_from_decl_token(decl_token);
    if (expected_instance == INVALID)
        return;

    uint expr_node = hir_stmt_record[stmt_slot(node, 2u)];
    uint call_node = first_array_call_node(expr_node);
    if (!valid_node(call_node))
        return;

    uint callee_token = call_callee_token(call_node);
    uint declared_instance = array_instance_from_callee_return(callee_token);
    if (declared_instance != INVALID &&
        same_bounded_array_instance(expected_instance, declared_instance))
        return;

    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint actual_instance = array_instance_from_name_token(name_token_for_expr(arg_node));
    if (actual_instance != INVALID &&
        same_bounded_array_instance(expected_instance, actual_instance))
        return;

    uint actual_ty = valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
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
}
