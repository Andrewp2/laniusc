// Publish pointer-jumped path leaf nodes onto HIR path/type records and expose
// leaf-to-owner links for bound predicate paths.

import generated_parse_production_ids;
import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_node_dense_id;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_type_path_leaf_value_a;

RWStructuredBuffer<uint> hir_type_value_node;
RWStructuredBuffer<uint> hir_type_path_leaf_node;
RWStructuredBuffer<uint> hir_type_path_owner_by_leaf;
RWStructuredBuffer<uint> hir_bound_path_owner_by_leaf;

static const uint INVALID = 0xffffffffu;
static const uint OWNER_NODE_MASK = 0x7fffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_PATH = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n || !valid_node(node))
        return;

    if (hir_kind[node] == HIR_PATH_EXPR)
    {
        uint leaf = hir_type_path_leaf_value_a[node];
        hir_type_path_leaf_node[node] = leaf;
    }

    // A type path root can sit below arbitrary grammar forwarding nodes. Join
    // the root to its nearest semantic HIR owner instead of assuming it is the
    // raw first child of the type row.
    if (node_kind[node] != PROD_TYPE_PATH && node_kind[node] != PROD_PATH &&
        node_kind[node] != PROD_BOUND_TYPE_PATH)
        return;
    uint path_row = hir_node_dense_id[node];
    uint owner_row = path_row != INVALID && path_row < active_node_count()
        ? hir_semantic_parent[path_row]
        : INVALID;
    uint owner = owner_row != INVALID && owner_row < active_node_count()
        ? hir_semantic_dense_node[owner_row]
        : INVALID;
    if (!valid_node(owner) || hir_kind[owner] != HIR_TYPE ||
        hir_type_form[owner] != HIR_TYPE_FORM_PATH)
        return;

    uint leaf = hir_type_path_leaf_value_a[node];
    hir_type_value_node[owner] = node;
    hir_type_path_leaf_node[owner] = leaf;
    if (valid_node(leaf))
    {
        if (node_kind[node] == PROD_BOUND_TYPE_PATH)
        {
            hir_bound_path_owner_by_leaf[leaf] = owner;
            return;
        }
        // Grammar wrapper records can publish the same leaf as their semantic
        // HIR_TYPE owner. Prefer the lower (outer semantic) node independent
        // of lane order while preserving zero as the host-clear sentinel.
        uint encoded_owner = OWNER_NODE_MASK - owner;
        atomic_u32_max(hir_type_path_owner_by_leaf, leaf, encoded_owner);
    }
}
