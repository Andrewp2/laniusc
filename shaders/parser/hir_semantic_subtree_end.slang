// Project original parse-tree subtree ends into dense semantic-HIR row space.
//
// Pareas compactification keeps the semantic node stream dense before later
// passes count and generate instructions. This pass records the dense
// one-past-end row for each semantic HIR row from the prefix count produced by
// hir_semantic_compact_scatter.

import gpu_index;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_semantic_prefix_before_node;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_semantic_subtree_end;

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

bool valid_original_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint dense_end_for_original_end(uint original_end, uint semantic_count)
{
    uint active_nodes = active_node_count();
    if (original_end >= active_nodes)
        return semantic_count;
    return min(hir_semantic_prefix_before_node[original_end], semantic_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint original_node = hir_semantic_dense_node[row];
    if (!valid_original_node(original_node))
    {
        hir_semantic_subtree_end[row] = row + 1u;
        return;
    }

    uint original_end = subtree_end[original_node];
    uint dense_end = dense_end_for_original_end(original_end, semantic_count);
    hir_semantic_subtree_end[row] = max(row + 1u, dense_end);
}
