// Builds up to eight levels of a heap-layout tree in one dispatch.
//
// A dispatch reads one level, the node_count nodes from start_node on (the
// leaves for mode 0, which writes them at leaf_base + i first), and each
// workgroup reduces its 256 nodes in workgroup memory, writing the `levels`
// levels above them. Level L's nodes are [L, 2L), so node k of the level at
// start S has its children at 2S + 2k and 2S + 2k + 1: a workgroup's nodes
// at every level come only from its own 256 inputs. A tree of 2^k leaves takes
// ceil(k / 8) dispatches rather than one per level (make_heap_build_steps).
//
// The including kernel includes heap_params.slang and defines, before
// including this file:
//   TREE_PARAMS          its ConstantBuffer of HeapTreeParams
//   TREE_VALUE           the node type
//   TREE_IDENTITY        the value of leaves past n_blocks
//   TREE_COMBINE(a, b)   the parent of two children
//   TREE_LEAF(i)         leaf i, for i < n_blocks
//   TREE_LOAD(node)      a node written by an earlier dispatch
//   TREE_STORE(node, v)  a statement writing a node
// A kernel whose params are laid out differently defines TREE_START_NODE,
// TREE_NODE_COUNT, TREE_MODE, TREE_LEVELS, TREE_N_BLOCKS and TREE_LEAF_BASE
// instead of using HeapTreeParams' fields.

#ifndef TREE_START_NODE
#define TREE_START_NODE TREE_PARAMS.start_node
#define TREE_NODE_COUNT TREE_PARAMS.node_count
#define TREE_MODE TREE_PARAMS.mode
#define TREE_LEVELS TREE_PARAMS.levels
#define TREE_N_BLOCKS TREE_PARAMS.n_blocks
#define TREE_LEAF_BASE TREE_PARAMS.leaf_base
#endif

static const uint HEAP_TILE = 256u;
static const uint HEAP_MAX_GROUPS_X = 65535u;

groupshared TREE_VALUE heap_tile[HEAP_TILE];

// The body of the including kernel's 256-lane main.
void heap_build(uint3 gid, uint3 ltid)
{
    uint lane = ltid.x;
    uint group = gid.x + gid.y * HEAP_MAX_GROUPS_X;
    uint i = group * HEAP_TILE + lane;
    uint level_start = TREE_START_NODE;
    uint count = TREE_NODE_COUNT;
    TREE_VALUE value = TREE_IDENTITY;
    if (i < count)
    {
        if (TREE_MODE == 0u)
        {
            if (i < TREE_N_BLOCKS) value = TREE_LEAF(i);
            TREE_STORE(TREE_LEAF_BASE + i, value);
        }
        else
        {
            value = TREE_LOAD(level_start + i);
        }
    }
    heap_tile[lane] = value;
    uint levels = TREE_LEVELS;
    for (uint level = 1u; level <= levels; level++)
    {
        GroupMemoryBarrierWithGroupSync();
        uint width = HEAP_TILE >> level;
        TREE_VALUE combined = TREE_IDENTITY;
        if (lane < width)
            combined = TREE_COMBINE(heap_tile[2u * lane], heap_tile[2u * lane + 1u]);
        GroupMemoryBarrierWithGroupSync();
        if (lane < width)
        {
            heap_tile[lane] = combined;
            uint index = group * width + lane;
            if (index < (count >> level))
                TREE_STORE((level_start >> level) + index, combined);
        }
    }
}
