// Builds all four delimiter minimum trees in one hierarchy traversal, eight
// levels per dispatch (tree/heap_levels.slang).

#include "../../tree/heap_params.slang"
ConstantBuffer<HeapTreeParams> gMinTree;

StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> bracket_match_block_min;
StructuredBuffer<int> angle_match_block_min;
RWStructuredBuffer<int> paren_match_min_tree;
RWStructuredBuffer<int> brace_match_min_tree;
RWStructuredBuffer<int> bracket_match_min_tree;
RWStructuredBuffer<int> angle_match_min_tree;

static const int INF = 2147483647;

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

#define TREE_PARAMS gMinTree
#define TREE_VALUE int4
#define TREE_IDENTITY int4(INF, INF, INF, INF)
#define TREE_COMBINE(a, b) min(a, b)
#define TREE_LEAF(i) int4(paren_match_block_min[i], brace_match_block_min[i], bracket_match_block_min[i], angle_match_block_min[i])
#define TREE_LOAD(node) load_tree(node)
#define TREE_STORE(node, v) store_tree(node, v)
#include "../../tree/heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
