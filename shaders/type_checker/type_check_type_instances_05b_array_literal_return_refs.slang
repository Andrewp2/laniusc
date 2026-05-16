// HIR array-literal return projection.
//
// This pass consumes return-statement records, expression/tree records, visible
// scalar types, function return type refs, and bounded array type-instance
// records. It publishes the array-return sentinel for `return [..];` when the
// literal's top-level element expressions match the enclosing function's
// bounded array element ref and literal length. It does not inspect token
// kinds, token spelling, source bytes, helper names, or punctuation.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;

static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_EXPR = 14u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;

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

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

bool has_ancestor_node(uint node, uint ancestor)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        if (cur == ancestor)
            return true;
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return false;
        cur = p;
    }
    return false;
}

bool has_intermediate_hir_kind(uint node, uint stop_ancestor, uint kind)
{
    uint cur = valid_node(node) ? parent[node] : INVALID;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return false;
        if (cur == stop_ancestor)
            return false;
        if (hir_kind[cur] == kind)
            return true;
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return false;
        cur = p;
    }
    return false;
}

uint owning_function_node(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (hir_kind[cur] == HIR_FN)
            return cur;

        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    if (type_instance_len_kind[payload] != TYPE_LEN_LITERAL)
        return INVALID;
    return payload;
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

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
}

bool publish_scalar_ref(uint ty, out uint tag, out uint payload)
{
    if (ty == TY_UNKNOWN || ty == INVALID || ty == ARRAY_RETURN_OK)
        return false;
    tag = TYPE_REF_SCALAR;
    payload = ty;
    return true;
}

uint visible_scalar_type_for_name_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN && ty != INVALID)
        return ty;

    uint decl_token = visible_decl[token];
    if (valid_token(decl_token))
    {
        ty = visible_type[decl_token];
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;
    }
    return TY_UNKNOWN;
}

uint first_descendant_with_hir_kind(uint root, uint kind)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == kind && has_ancestor_node(node, root))
            return node;
    }
    return INVALID;
}

uint first_descendant_with_production(uint root, uint prod)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (node_kind[node] == prod && has_ancestor_node(node, root))
            return node;
    }
    return INVALID;
}

uint array_literal_for_return_expr(uint return_expr)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_ARRAY_EXPR || !has_ancestor_node(node, return_expr))
            continue;
        if (!has_intermediate_hir_kind(node, return_expr, HIR_ARRAY_EXPR))
            return node;
    }
    return INVALID;
}

bool top_level_array_element_expr(uint expr_node, uint array_node)
{
    if (hir_kind[expr_node] != HIR_EXPR || !has_ancestor_node(expr_node, array_node))
        return false;
    if (has_intermediate_hir_kind(expr_node, array_node, HIR_EXPR))
        return false;
    if (has_intermediate_hir_kind(expr_node, array_node, HIR_ARRAY_EXPR))
        return false;
    return true;
}

bool index_expr_ref(uint index_node, out uint tag, out uint payload)
{
    uint index_token = hir_token_pos[index_node];
    if (!valid_token(index_token))
        return false;

    uint ty = call_return_type[index_token];
    return publish_scalar_ref(ty, tag, payload);
}

bool literal_or_name_expr_ref(uint expr_node, out uint tag, out uint payload)
{
    uint int_node = first_descendant_with_production(expr_node, PROD_INT);
    if (valid_node(int_node))
        return publish_scalar_ref(TY_INT, tag, payload);

    uint true_node = first_descendant_with_production(expr_node, PROD_TRUE);
    uint false_node = first_descendant_with_production(expr_node, PROD_FALSE);
    if (valid_node(true_node) || valid_node(false_node))
        return publish_scalar_ref(TY_BOOL, tag, payload);

    uint name_node = first_descendant_with_hir_kind(expr_node, HIR_NAME_EXPR);
    if (valid_node(name_node))
    {
        uint name_token = hir_token_pos[name_node];
        return publish_scalar_ref(visible_scalar_type_for_name_token(name_token), tag, payload);
    }

    return false;
}

bool expr_type_ref(uint expr_node, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;

    uint index_node = first_descendant_with_hir_kind(expr_node, HIR_INDEX_EXPR);
    if (valid_node(index_node))
        return index_expr_ref(index_node, tag, payload);

    return literal_or_name_expr_ref(expr_node, tag, payload);
}

bool array_literal_matches_return_instance(uint array_node, uint dst_instance)
{
    if (dst_instance == INVALID)
        return false;

    uint elem_tag = type_instance_elem_ref_tag[dst_instance];
    uint elem_payload = type_instance_elem_ref_payload[dst_instance];
    uint expected_len = type_instance_len_payload[dst_instance];
    uint count = 0u;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (!top_level_array_element_expr(node, array_node))
            continue;

        uint actual_tag = 0u;
        uint actual_payload = INVALID;
        if (!expr_type_ref(node, actual_tag, actual_payload))
            return false;
        if (!same_type_ref(elem_tag, elem_payload, actual_tag, actual_payload))
            return false;

        count += 1u;
    }

    return count == expected_len;
}

void publish_array_literal_return(uint return_node)
{
    if (hir_kind[return_node] != HIR_RETURN_STMT ||
        hir_stmt_record[stmt_slot(return_node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[return_node];
    if (!valid_token(return_token))
        return;

    uint return_expr = hir_stmt_record[stmt_slot(return_node, 1u)];
    if (!valid_node(return_expr))
        return;

    uint array_node = array_literal_for_return_expr(return_expr);
    if (!valid_node(array_node))
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (array_literal_matches_return_instance(array_node, dst_instance))
        call_return_type[return_token] = ARRAY_RETURN_OK;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    publish_array_literal_return(node);
}
