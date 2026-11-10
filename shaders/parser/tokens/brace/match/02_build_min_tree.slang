// Build the block-minimum tree of one delimiter's match depths, eight levels
// per dispatch (tree/heap_levels.slang).

#include "../../../tree/heap_params.slang"
ConstantBuffer<HeapTreeParams> gMinTree;
StructuredBuffer<int> brace_match_block_min;
RWStructuredBuffer<int> brace_match_min_tree;
static const int INF = 2147483647;

#define TREE_PARAMS gMinTree
#define TREE_VALUE int
#define TREE_IDENTITY INF
#define TREE_COMBINE(a, b) min(a, b)
#define TREE_LEAF(i) brace_match_block_min[i]
#define TREE_LOAD(node) brace_match_min_tree[node]
#define TREE_STORE(node, v) brace_match_min_tree[node] = (v)
#include "../../../tree/heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
