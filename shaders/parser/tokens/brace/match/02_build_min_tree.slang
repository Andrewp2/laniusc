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

StructuredBuffer<int> brace_match_block_min;
RWStructuredBuffer<int> brace_match_min_tree;

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
        brace_match_min_tree[gMinTree.leaf_base + i] =
            (i < gMinTree.n_blocks) ? brace_match_block_min[i] : INF;
        return;
    }

    uint node = gMinTree.start_node + i;
    int left = brace_match_min_tree[node * 2u];
    int right = brace_match_min_tree[node * 2u + 1u];
    brace_match_min_tree[node] = min(left, right);
}
