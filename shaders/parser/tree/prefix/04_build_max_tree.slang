// Build a heap-layout max tree over 256-prefix-block maxima.
//
// Leaves live at [leaf_base, 2 * leaf_base). Internal nodes are built bottom
// up, eight levels per dispatch (tree/heap_levels.slang), so parent/span
// recovery can locate a candidate block with a logarithmic range search
// instead of walking blocks.

#include "../heap_params.slang"
ConstantBuffer<HeapTreeParams> gMaxTree;

StructuredBuffer<int> prefix_block_max;
RWStructuredBuffer<int> prefix_block_max_tree;

static const int NEG_INF = -2147483647;

#define TREE_PARAMS gMaxTree
#define TREE_VALUE int
#define TREE_IDENTITY NEG_INF
#define TREE_COMBINE(a, b) max(a, b)
#define TREE_LEAF(i) prefix_block_max[i]
#define TREE_LOAD(node) prefix_block_max_tree[node]
#define TREE_STORE(node, v) prefix_block_max_tree[node] = (v)
#include "../heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
