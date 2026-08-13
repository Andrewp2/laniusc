// Count preceding siblings with one independent local traversal per semantic
// row. Dense preorder makes row zero the first root; non-root walks begin at
// their parent's first child and follow the materialized sibling chain.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_semantic_first_child;
StructuredBuffer<uint> hir_semantic_next_sibling;
RWStructuredBuffer<uint> hir_semantic_child_index;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u
               ? min(gHirSemantic.n, tree_count_status[5u])
               : gHirSemantic.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_semantic_row(uint row, uint semantic_count)
{
    return row != INVALID && row < semantic_count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint parent = hir_semantic_parent[row];
    uint sibling = valid_semantic_row(parent, semantic_count)
                       ? hir_semantic_first_child[parent]
                       : 0u;
    uint index = 0u;
    while (valid_semantic_row(sibling, semantic_count) &&
           sibling != row && index < semantic_count)
    {
        index += 1u;
        sibling = hir_semantic_next_sibling[sibling];
    }
    hir_semantic_child_index[row] = index;
}
