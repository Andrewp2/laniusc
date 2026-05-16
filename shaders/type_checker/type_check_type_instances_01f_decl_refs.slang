// HIR declaration type-reference projection.
//
// This pass publishes declaration-token keyed type refs for local lets,
// constants, and named parameters. Later semantic passes consume these records
// instead of deriving declaration type heads from token offsets.

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
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;

static const uint TYPE_REF_INVALID = 0u;

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
    for (uint guard = 0u; guard < 96u; guard += 1u)
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

uint first_descendant_with_production(uint root, uint prod)
{
    if (!valid_node(root))
        return INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (node_kind[node] == prod && has_ancestor_node(node, root))
            return node;
    }
    return INVALID;
}

uint first_child_node(uint node)
{
    uint child = valid_node(node) ? first_child[node] : INVALID;
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    uint sibling = valid_node(node) ? next_sibling[node] : INVALID;
    return valid_node(sibling) ? sibling : INVALID;
}

uint first_type_descendant(uint root)
{
    if (!valid_node(root))
        return INVALID;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == HIR_TYPE && has_ancestor_node(node, root))
            return node;
    }
    return INVALID;
}

uint let_type_node(uint let_node)
{
    uint let_type = first_descendant_with_production(let_node, PROD_LET_TYPE);
    return first_type_descendant(let_type);
}

uint const_type_node(uint const_node)
{
    return first_type_descendant(const_node);
}

uint param_type_node(uint param_node)
{
    uint param_prod = valid_node(param_node) ? node_kind[param_node] : INVALID;
    if (param_prod == PROD_PARAM_SELF_REF)
        return INVALID;
    if (param_prod == PROD_PARAM_SELF)
    {
        uint child = first_child_node(param_node);
        [loop]
        for (uint guard = 0u; guard < 8u && child != INVALID; guard += 1u)
        {
            if (node_kind[child] == PROD_SELF_PARAM_TYPED)
                return first_type_descendant(child);
            child = next_sibling_node(child);
        }
        return INVALID;
    }
    return first_type_descendant(param_node);
}

void publish_decl_ref(uint decl_token, uint type_node)
{
    if (!valid_token(decl_token) || !valid_node(type_node))
        return;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_INVALID)
        return;

    decl_type_ref_tag[decl_token] = tag;
    decl_type_ref_payload[decl_token] = payload;
}

void publish_stmt_decl_ref(uint node)
{
    uint kind = hir_stmt_record[stmt_slot(node, 0u)];
    if (kind != STMT_RECORD_KIND_LET && kind != STMT_RECORD_KIND_CONST)
        return;

    uint decl_token = hir_stmt_record[stmt_slot(node, 1u)];
    uint type_node = kind == STMT_RECORD_KIND_LET ? let_type_node(node)
                                                  : const_type_node(node);
    publish_decl_ref(decl_token, type_node);
}

void publish_param_decl_ref(uint node)
{
    if (hir_kind[node] != HIR_PARAM)
        return;

    uint4 record = hir_param_record[node];
    uint decl_token = record.z;
    publish_decl_ref(decl_token, param_type_node(node));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    publish_stmt_decl_ref(node);
    publish_param_decl_ref(node);
}
