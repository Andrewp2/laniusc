// Build a heap-layout max tree over 256-prefix-block maxima.
//
// Leaves live at [leaf_base, 2 * leaf_base). Internal nodes are built in
// separate dispatches from the bottom up, so parent/span recovery can locate a
// candidate block with a logarithmic range search instead of walking blocks.

struct Params
{
    uint n_blocks;
    uint leaf_base;
    uint start_node;
    uint node_count;
    uint mode;
    uint _pad0;
    uint _pad1;
    uint _pad2;
};
ConstantBuffer<Params> gMaxTree;

StructuredBuffer<int> prefix_block_max;
RWStructuredBuffer<int> prefix_block_max_tree;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const int NEG_INF = -2147483647;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gMaxTree.node_count)
        return;

    if (gMaxTree.mode == 0u)
    {
        prefix_block_max_tree[gMaxTree.leaf_base + i] =
            (i < gMaxTree.n_blocks) ? prefix_block_max[i] : NEG_INF;
        return;
    }

    uint node = gMaxTree.start_node + i;
    int left = prefix_block_max_tree[node * 2u];
    int right = prefix_block_max_tree[node * 2u + 1u];
    prefix_block_max_tree[node] = max(left, right);
}
