// Builds all four delimiter minimum trees in one hierarchy traversal.

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

StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> bracket_match_block_min;
StructuredBuffer<int> angle_match_block_min;
RWStructuredBuffer<int> paren_match_min_tree;
RWStructuredBuffer<int> brace_match_min_tree;
RWStructuredBuffer<int> bracket_match_min_tree;
RWStructuredBuffer<int> angle_match_min_tree;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const int INF = 2147483647;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

void store_tree(uint node, int4 value)
{
    paren_match_min_tree[node] = value.x;
    brace_match_min_tree[node] = value.y;
    bracket_match_min_tree[node] = value.z;
    angle_match_min_tree[node] = value.w;
}

int4 load_tree(uint node)
{
    return int4(
        paren_match_min_tree[node],
        brace_match_min_tree[node],
        bracket_match_min_tree[node],
        angle_match_min_tree[node]);
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
        int4 value = i < gMinTree.n_blocks
            ? int4(
                paren_match_block_min[i],
                brace_match_block_min[i],
                bracket_match_block_min[i],
                angle_match_block_min[i])
            : int4(INF, INF, INF, INF);
        store_tree(gMinTree.leaf_base + i, value);
        return;
    }

    uint node = gMinTree.start_node + i;
    store_tree(node, min(load_tree(node * 2u), load_tree(node * 2u + 1u)));
}
