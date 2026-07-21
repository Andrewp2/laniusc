// Build the block-minimum tree used by Pareas-style previous-smaller-or-equal
// stack-effect validation. Leaves convert block-local minima into global
// depths; later levels reduce them with min.

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

ConstantBuffer<Params> gMinTree;

StructuredBuffer<int> block_row_min;
StructuredBuffer<int> block_prefix;
RWStructuredBuffer<int> min_tree;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const int INF = 2147483647;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gMinTree.node_count)
        return;

    if (gMinTree.mode == 0u)
    {
        min_tree[gMinTree.leaf_base + i] = i < gMinTree.n_blocks
            ? block_prefix[i] + block_row_min[i]
            : INF;
        return;
    }

    uint node = gMinTree.start_node + i;
    min_tree[node] = min(min_tree[node * 2u], min_tree[node * 2u + 1u]);
}
