// Project dense semantic-HIR first-child and next-sibling links.
//
// The dense semantic tree is preorder. Once nearest semantic parents and
// dense subtree ends are known, child/sibling navigation is a local record
// projection:
//   - first child is row + 1 when its parent is row
//   - next sibling is subtree_end[row] when it has the same parent

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_subtree_end;
StructuredBuffer<uint> hir_semantic_parent;

RWStructuredBuffer<uint> hir_semantic_first_child;
RWStructuredBuffer<uint> hir_semantic_next_sibling;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_ll1 != 0u ? min(gHirSemantic.n, ll1_status[5u]) : gHirSemantic.n;
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

    uint child = row + 1u;
    hir_semantic_first_child[row] =
        valid_semantic_row(child, semantic_count) &&
        hir_semantic_parent[child] == row ? child : INVALID;

    uint sibling = hir_semantic_subtree_end[row];
    uint parent = hir_semantic_parent[row];
    hir_semantic_next_sibling[row] =
        valid_semantic_row(sibling, semantic_count) &&
        hir_semantic_parent[sibling] == parent ? sibling : INVALID;
}
