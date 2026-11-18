// The upper heap over closure token blocks. Each local heap stores its
// minimum again in row zero, so it also supplies the upper heap's leaves.
#include "../parser/tree/heap_params.slang"
ConstantBuffer<HeapTreeParams> gMinTree;

StructuredBuffer<int> depth_local_min;
RWStructuredBuffer<int> depth_min_tree;

#define TREE_PARAMS gMinTree
#define TREE_VALUE int
#define TREE_IDENTITY 2147483647
#define TREE_COMBINE(a, b) min(a, b)
#define TREE_LEAF(i) depth_local_min[(i) * 256u]
#define TREE_LOAD(node) depth_min_tree[node]
#define TREE_STORE(node, v) depth_min_tree[node] = v
#include "../parser/tree/heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
