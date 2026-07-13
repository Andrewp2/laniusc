// Seed nearest-semantic-parent pointer jumping over the original parse tree.
//
// The semantic HIR stream is already compacted into dense rows. This pass
// initializes a Pareas-style hybrid parent-link rewrite. Each lane first walks
// a bounded block locally, which is efficient for the short chains common in
// parse trees, and leaves a block link for logarithmic Hillis-Steele rounds.
// The bounded walk keeps the worst case logarithmic without paying one global
// read/write round per individual parent edge.

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
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

    uint ancestor = parent[node];
    uint local_span = max(1u, gHirSemantic.semantic_parent_local_ancestor_span);
    for (uint hop = 0u; hop < local_span; ++hop)
    {
        if (!valid_node(ancestor) || ancestor == node)
            return;
        if (hir_kind[ancestor] != HIR_NONE)
        {
            hir_semantic_parent_value_a[node] = hir_node_dense_id[ancestor];
            return;
        }

        // Keep the final examined non-semantic node as the block link. Its own
        // independently initialized row represents the following block.
        if (hop + 1u == local_span)
        {
            hir_semantic_parent_link_a[node] = ancestor;
            return;
        }
        uint next = parent[ancestor];
        if (!valid_node(next) || next == ancestor)
            return;
        ancestor = next;
    }
}
