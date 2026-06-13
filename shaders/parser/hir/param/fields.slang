// Publish parser-owned function parameter metadata from pointer-jumped links.
//
// Parameter consumers should use these rows instead of deriving parameter
// identity or ordinal from token neighborhoods. Owner and ordinal are produced
// by the preceding linked-list passes, not by walking ancestors here.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_param_owner_a;
StructuredBuffer<uint> hir_param_rank_a;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint4> hir_param_record;
RWStructuredBuffer<uint> hir_param_type_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_NONE = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirParam.uses_status_count != 0u ? min(gHirParam.n, tree_count_status[5u]) : gHirParam.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

bool valid_type_node(uint node)
{
    return valid_node(node) && hir_kind[node] == HIR_TYPE &&
           hir_type_form[node] != HIR_TYPE_FORM_NONE;
}

uint direct_type_child(uint root)
{
    uint child = first_child_node(root);
    return valid_type_node(child) ? child : INVALID;
}

uint self_parameter_type_node(uint node)
{
    uint tail = first_child_node(node);
    if (!valid_node(tail) || node_kind[tail] != PROD_SELF_PARAM_TYPED)
        return INVALID;

    return direct_type_child(tail);
}

uint parameter_type_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint prod = node_kind[node];
    if (prod == PROD_PARAM_SELF_REF)
        return INVALID;
    if (prod == PROD_PARAM_SELF)
        return self_parameter_type_node(node);
    return direct_type_child(node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID)
        return;

    hir_param_record[node] = uint4(INVALID, INVALID, INVALID, INVALID);
    if (hir_kind[node] != HIR_PARAM)
        return;

    uint fn_node = hir_param_owner_a[node];
    if (!valid_node(fn_node))
        return;

    uint name_token = hir_token_pos[node];
    if (name_token == INVALID)
        return;

    hir_param_record[node] = uint4(
        fn_node,
        hir_param_rank_a[node],
        name_token,
        node);
    hir_param_type_node[node] = parameter_type_node(node);
}
