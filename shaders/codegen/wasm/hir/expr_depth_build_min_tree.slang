// Build the perfect block-minimum tree used by previous-smaller-or-equal.

struct Params
{
    uint n_blocks;
    uint leaf_base;
    uint start_node;
    uint node_count;
    uint mode;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gExprDepthTree;

StructuredBuffer<uint> expr_depth_block_min;
RWStructuredBuffer<uint> expr_depth_min_tree;

static const uint INF = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (i >= gExprDepthTree.node_count)
        return;

    if (gExprDepthTree.mode == 0u)
    {
        expr_depth_min_tree[gExprDepthTree.leaf_base + i] =
            i < gExprDepthTree.n_blocks ? expr_depth_block_min[i] : INF;
        return;
    }

    uint node = gExprDepthTree.start_node + i;
    expr_depth_min_tree[node] = min(
        expr_depth_min_tree[node * 2u],
        expr_depth_min_tree[node * 2u + 1u]);
}
