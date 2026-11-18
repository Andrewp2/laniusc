// Builds the four delimiter minimum trees and the statement boundary tree in
// one hierarchy traversal, eight levels per dispatch (tree/heap_levels.slang).

#include "../../tree/heap_params.slang"
ConstantBuffer<HeapTreeParams> gMinTree;

StructuredBuffer<int> paren_match_block_min;
StructuredBuffer<int> brace_match_block_min;
StructuredBuffer<int> bracket_match_block_min;
StructuredBuffer<int> angle_match_block_min;
StructuredBuffer<int> statement_boundary_block_min;
RWStructuredBuffer<int> paren_match_min_tree;
RWStructuredBuffer<int> brace_match_min_tree;
RWStructuredBuffer<int> bracket_match_min_tree;
RWStructuredBuffer<int> angle_match_min_tree;
RWStructuredBuffer<int> statement_boundary_min_tree;

static const int INF = 2147483647;

// One node of all five trees.
struct Minima
{
    int4 delimiters;
    int boundary;
};

Minima minima(int4 delimiters, int boundary)
{
    Minima value;
    value.delimiters = delimiters;
    value.boundary = boundary;
    return value;
}

void store_tree(uint node, Minima value)
{
    paren_match_min_tree[node] = value.delimiters.x;
    brace_match_min_tree[node] = value.delimiters.y;
    bracket_match_min_tree[node] = value.delimiters.z;
    angle_match_min_tree[node] = value.delimiters.w;
    statement_boundary_min_tree[node] = value.boundary;
}

Minima load_tree(uint node)
{
    return minima(
        int4(
            paren_match_min_tree[node],
            brace_match_min_tree[node],
            bracket_match_min_tree[node],
            angle_match_min_tree[node]),
        statement_boundary_min_tree[node]);
}

Minima load_leaf(uint block)
{
    return minima(
        int4(
            paren_match_block_min[block],
            brace_match_block_min[block],
            bracket_match_block_min[block],
            angle_match_block_min[block]),
        statement_boundary_block_min[block]);
}

#define TREE_PARAMS gMinTree
#define TREE_VALUE Minima
#define TREE_IDENTITY minima(int4(INF, INF, INF, INF), INF)
#define TREE_COMBINE(a, b) minima(min(a.delimiters, b.delimiters), min(a.boundary, b.boundary))
#define TREE_LEAF(i) load_leaf(i)
#define TREE_LOAD(node) load_tree(node)
#define TREE_STORE(node, v) store_tree(node, v)
#include "../../tree/heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
