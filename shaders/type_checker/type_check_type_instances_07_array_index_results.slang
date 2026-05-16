// HIR array/slice index result projection.
//
// This pass consumes parser-owned index-expression records, visible-decl
// records, declaration type refs, and array/slice type-instance records. It
// publishes the element type at the index-expression token for later type
// checks. It does not inspect token kinds, token spelling, source bytes, or
// generic parameter token neighborhoods.

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
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_value_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_state;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint HIR_EXPR = 14u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;

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

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint p = parent[node];
    if (!valid_node(p))
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint candidate = 0u; candidate < n; candidate += 1u)
    {
        if (parent[candidate] == p && next_sibling[candidate] == node)
            return candidate;
    }
    return INVALID;
}

uint base_node_for_index(uint index_node)
{
    uint p = valid_node(index_node) ? parent[index_node] : INVALID;
    if (!valid_node(p))
        return INVALID;

    uint previous = previous_sibling_node(index_node);
    if (valid_node(previous))
        return previous;

    return hir_kind[p] == HIR_POSTFIX_EXPR ? p : INVALID;
}

uint first_name_token_descendant(uint root)
{
    if (!valid_node(root))
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_NAME_EXPR || !has_ancestor_node(node, root))
            continue;

        uint token = hir_expr_value_token[node];
        if (valid_token(token))
            return token;

        token = hir_token_pos[node];
        if (valid_token(token))
            return token;
    }
    return INVALID;
}

bool scalar_atom_type(uint node, out uint ty)
{
    ty = TY_UNKNOWN;

    uint prod = node_kind[node];
    if (prod == PROD_INT)
    {
        ty = TY_INT;
        return true;
    }
    if (prod == PROD_TRUE || prod == PROD_FALSE)
    {
        ty = TY_BOOL;
        return true;
    }
    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint token = hir_expr_value_token[node];
        if (!valid_token(token))
            token = hir_token_pos[node];
        if (!valid_token(token))
            return false;

        uint decl_token = visible_decl[token];
        if (!valid_token(decl_token))
            return false;
        if (decl_type_ref_tag[decl_token] != TYPE_REF_SCALAR)
            return false;

        ty = decl_type_ref_payload[decl_token];
        return ty != TY_UNKNOWN;
    }

    return false;
}

uint index_operand_scalar_type(uint index_node)
{
    uint found_ty = TY_UNKNOWN;
    uint atom_count = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (!has_ancestor_node(node, index_node))
            continue;

        uint atom_ty = TY_UNKNOWN;
        if (!scalar_atom_type(node, atom_ty))
            continue;

        atom_count += 1u;
        found_ty = atom_ty;
        if (atom_count > 1u)
            return TY_UNKNOWN;
    }
    return atom_count == 1u ? found_ty : TY_UNKNOWN;
}

bool generic_decl_production(uint prod)
{
    return prod == PROD_FN || prod == PROD_EXTERN_FN || prod == PROD_STRUCT ||
           prod == PROD_ENUM || prod == PROD_TYPE_ALIAS;
}

uint generic_decl_ancestor(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (generic_decl_production(node_kind[cur]))
            return cur;
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

uint first_node_at_token(uint token)
{
    if (!valid_token(token))
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_token_pos[node] == token)
            return node;
    }
    return INVALID;
}

uint generic_param_decl_for_ref_token(uint token)
{
    uint use_node = first_node_at_token(token);
    uint use_decl = generic_decl_ancestor(use_node);
    if (!valid_node(use_decl))
        return INVALID;

    uint name_id = name_id_by_token[token];
    if (name_id == INVALID)
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (node_kind[node] != PROD_ENUM_TYPE_PARAM || generic_decl_ancestor(node) != use_decl)
            continue;

        uint decl_token = hir_token_pos[node];
        if (valid_token(decl_token) && name_id_by_token[decl_token] == name_id)
            return decl_token;
    }
    return INVALID;
}

uint type_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_state[payload] != TYPE_INSTANCE_RESOLVED)
        return INVALID;

    uint kind = type_instance_kind[payload];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return INVALID;

    return payload;
}

uint array_or_slice_instance_from_decl(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    return type_instance_from_ref(decl_type_ref_tag[decl_token], decl_type_ref_payload[decl_token]);
}

uint array_or_slice_instance_for_base_node(uint base_node)
{
    if (!valid_node(base_node))
        return INVALID;

    uint base_token = first_name_token_descendant(base_node);
    if (!valid_token(base_token))
        return INVALID;

    uint decl_token = visible_decl[base_token];
    return array_or_slice_instance_from_decl(decl_token);
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;

    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_token = generic_param_decl_for_ref_token(payload);
        return decl_token == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_token;
    }

    return TY_UNKNOWN;
}

void publish_index_result(uint index_node)
{
    uint result_token = hir_token_pos[index_node];
    if (!valid_token(result_token))
        return;
    if (index_operand_scalar_type(index_node) != TY_INT)
        return;

    uint base_node = base_node_for_index(index_node);
    uint instance = array_or_slice_instance_for_base_node(base_node);
    if (instance == INVALID)
        return;

    uint elem_ty = type_ref_to_type_code(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
    if (elem_ty != TY_UNKNOWN)
        call_return_type[result_token] = elem_ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_INDEX_EXPR)
        return;

    publish_index_result(node);
}
