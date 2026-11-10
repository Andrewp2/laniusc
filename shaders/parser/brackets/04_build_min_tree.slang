// Build the block-minimum tree used by Pareas-style previous-smaller-or-equal
// stack-effect validation. Leaves are the roots of the blocks' local layer
// heaps from 03_apply_prefix; later levels reduce them with min. Together
// with the local heaps this is the two-level heap pse_04_pair_by_layer
// searches (blocked_search_tree.slang). Blocks past the stack changes keep
// stale heaps. A search descends only into blocks before its own; a low stale
// root only delays a miss.

#include "../tree/heap_params.slang"
ConstantBuffer<HeapTreeParams> gMinTree;

StructuredBuffer<int> layer_local_min;
RWStructuredBuffer<int> min_tree;

static const uint WG_SIZE = 256u;
static const int INF = 2147483647;

#define TREE_PARAMS gMinTree
#define TREE_VALUE int
#define TREE_IDENTITY INF
#define TREE_COMBINE(a, b) min(a, b)
#define TREE_LEAF(i) layer_local_min[(i) * WG_SIZE]
#define TREE_LOAD(node) min_tree[node]
#define TREE_STORE(node, v) min_tree[node] = (v)
#include "../tree/heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
