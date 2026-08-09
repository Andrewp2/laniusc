// Seed nearest-match-arm propagation over the raw parse tree.
//
// Pattern nesting is unbounded, so ownership cannot be recovered with a
// grammar-shaped fixed walk. Each lane examines a short local parent span and
// leaves the remaining relation for the shared logarithmic pointer-jump pass.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;

RWStructuredBuffer<uint> hir_semantic_parent_link_a;
RWStructuredBuffer<uint> hir_match_nearest_arm;

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
    hir_match_nearest_arm[node] = INVALID;

    if (!valid_node(node))
        return;

    uint ancestor = parent[node];
    uint local_span = max(1u, gHirSemantic.semantic_parent_local_ancestor_span);
    for (uint hop = 0u; hop < local_span; ++hop)
    {
        if (!valid_node(ancestor) || ancestor == node)
            return;
        if (node_kind[ancestor] == PROD_MATCH_ARM)
        {
            hir_match_nearest_arm[node] = ancestor;
            return;
        }
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
