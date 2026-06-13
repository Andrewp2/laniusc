// Seed nearest-semantic-parent pointer jumping over the original parse tree.
//
// The semantic HIR stream is already compacted into dense rows. This pass
// initializes a Pareas-style parent-link rewrite: each original parse node
// points at its parse parent and carries the dense row of that parent when the
// parent is itself semantic HIR.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_node_dense_id;

RWStructuredBuffer<uint> hir_semantic_parent_link_a;
RWStructuredBuffer<uint> hir_semantic_parent_value_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_NONE = 0u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirSemantic.n)
        return;

    hir_semantic_parent_link_a[node] = INVALID;
    hir_semantic_parent_value_a[node] = INVALID;

    if (!valid_node(node))
        return;

    uint p = parent[node];
    if (!valid_node(p) || p == node)
        return;

    hir_semantic_parent_link_a[node] = p;
    if (hir_kind[p] != HIR_NONE)
        hir_semantic_parent_value_a[node] = hir_node_dense_id[p];
}
