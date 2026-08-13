// Project the nearest semantic parent directly into dense HIR row space. One
// lane owns one semantic row and locally traverses its raw parent chain.

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_node_dense_id;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_semantic_parent;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint node = hir_semantic_dense_node[row];
    if (!valid_node(node))
    {
        hir_semantic_parent[row] = INVALID;
        return;
    }

    uint ancestor = parent[node];
    uint visited = 0u;
    while (valid_node(ancestor) && visited < active_node_count())
    {
        uint dense_parent = hir_node_dense_id[ancestor];
        if (dense_parent < semantic_count)
        {
            hir_semantic_parent[row] = dense_parent;
            return;
        }
        ancestor = parent[ancestor];
        visited += 1u;
    }
    hir_semantic_parent[row] = INVALID;
}
