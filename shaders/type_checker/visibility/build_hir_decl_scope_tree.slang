// Build internal max-scope nodes for HIR declaration range queries.
//
// Scheduling contract:
// - Dispatch after type_check_visible_03g_build_hir_decl_scope_leaves. Each
//   dispatch reads the level from level_start (level_count nodes) and builds
//   up to eight levels above it (parser/tree/heap_levels.slang).
// - Each node stores max(left_scope_end, right_scope_end).
// - This is a GPU-resident reduction over compact HIR declaration records.

struct Params
{
    uint decl_capacity;
    uint row_block_size;
    uint leaf_base;
    uint level_start;
    uint level_count;
    uint levels;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> hir_visible_decl_scope_tree;

#define TREE_START_NODE gParams.level_start
#define TREE_NODE_COUNT gParams.level_count
#define TREE_MODE 1u
#define TREE_LEVELS gParams.levels
#define TREE_N_BLOCKS 0u
#define TREE_LEAF_BASE gParams.leaf_base
#define TREE_VALUE uint
#define TREE_IDENTITY 0u
#define TREE_COMBINE(a, b) max(a, b)
#define TREE_LEAF(i) 0u
#define TREE_LOAD(node) hir_visible_decl_scope_tree[node]
#define TREE_STORE(node, v) hir_visible_decl_scope_tree[node] = (v)
#include "../../parser/tree/heap_levels.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    heap_build(gid, ltid);
}
