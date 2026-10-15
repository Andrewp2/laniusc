// Find each semantic row's index among its siblings with a range query over
// the child-index heaps (index_tree.slang): the number of earlier siblings
// is how often the parent's row + 1 occurs as the minimum of parent + 1 over
// the rows between the parent and the row. One lane owns one row and reads
// O(log distance) heap nodes instead of walking the sibling chain, which
// runs through long statement and item lists.

import parser.hir.semantic.parent.end_tree;
import parser.hir.semantic.child.index.index_tree;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint2> hir_semantic_child_local;
StructuredBuffer<uint2> hir_semantic_child_blocks;
StructuredBuffer<uint2> hir_semantic_child_top;

RWStructuredBuffer<uint> hir_semantic_child_index;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_semantic_count()
{
    uint active_nodes = gHirSemantic.uses_status_count != 0u
        ? min(gHirSemantic.n, tree_count_status[5u])
        : gHirSemantic.n;
    return min(hir_semantic_count[0u], active_nodes);
}

// Local heap node 1 <= node < 512 of block: rows from node 256 on.
uint2 local_node(uint block, uint node)
{
    if (node >= CHILD_INDEX_FANOUT)
        return child_index_leaf(
            hir_semantic_parent[block * CHILD_INDEX_FANOUT + node - CHILD_INDEX_FANOUT]);
    return hir_semantic_child_local[block * CHILD_INDEX_FANOUT + node];
}

// Node of the heap over the blocks: a block's aggregate from the leaf base
// on, a node of a group's heap down to the group roots, and a top heap node
// above them (the layout of SemanticEndTree.block_node).
uint2 block_node(uint node, uint leaf_base, uint active_blocks)
{
    if (node >= leaf_base)
    {
        uint block = node - leaf_base;
        return block < active_blocks
            ? hir_semantic_child_local[block * CHILD_INDEX_FANOUT]
            : ChildIndexMinCount.identity();
    }
    uint groups = leaf_base / CHILD_INDEX_FANOUT;
    if (node < groups)
        return hir_semantic_child_top[node];
    uint depth = uint(firstbithigh(node)) - uint(firstbithigh(groups));
    uint group = (node >> depth) - groups;
    uint local = (1u << depth) | (node & ((1u << depth) - 1u));
    return hir_semantic_child_blocks[group * CHILD_INDEX_FANOUT + local];
}

// The aggregate of rows block * 256 + [lo, hi), 0 <= lo <= hi <= 256.
uint2 local_range(uint block, uint lo, uint hi)
{
    uint2 acc = ChildIndexMinCount.identity();
    uint l = CHILD_INDEX_FANOUT + lo;
    uint r = CHILD_INDEX_FANOUT + hi;
    for (uint step = 0u; step < 9u; step += 1u)
    {
        if (l >= r)
            break;
        if ((l & 1u) != 0u)
        {
            acc = ChildIndexMinCount.combine(acc, local_node(block, l));
            l += 1u;
        }
        if ((r & 1u) != 0u)
        {
            r -= 1u;
            acc = ChildIndexMinCount.combine(acc, local_node(block, r));
        }
        l >>= 1u;
        r >>= 1u;
    }
    return acc;
}

// The aggregate of blocks [lo, hi).
uint2 block_range(uint lo, uint hi, uint active_blocks)
{
    uint leaf_base = semantic_end_leaf_base(gHirSemantic.n);
    uint2 acc = ChildIndexMinCount.identity();
    uint l = leaf_base + lo;
    uint r = leaf_base + hi;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (l >= r)
            break;
        if ((l & 1u) != 0u)
        {
            acc = ChildIndexMinCount.combine(acc, block_node(l, leaf_base, active_blocks));
            l += 1u;
        }
        if ((r & 1u) != 0u)
        {
            r -= 1u;
            acc = ChildIndexMinCount.combine(acc, block_node(r, leaf_base, active_blocks));
        }
        l >>= 1u;
        r >>= 1u;
    }
    return acc;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    // Roots (and rows without a valid parent) count the earlier roots, whose
    // parent + 1 wraps to 0.
    uint parent = hir_semantic_parent[row];
    uint target = parent < semantic_count ? parent + 1u : 0u;
    uint index = 0u;
    if (target < row)
    {
        uint first_block = target / CHILD_INDEX_FANOUT;
        uint last_block = (row - 1u) / CHILD_INDEX_FANOUT;
        uint first_lo = target % CHILD_INDEX_FANOUT;
        uint last_hi = (row - 1u) % CHILD_INDEX_FANOUT + 1u;
        uint2 range;
        if (first_block == last_block)
        {
            range = local_range(first_block, first_lo, last_hi);
        }
        else
        {
            uint active_blocks =
                (semantic_count + CHILD_INDEX_FANOUT - 1u) / CHILD_INDEX_FANOUT;
            range = ChildIndexMinCount.combine(
                ChildIndexMinCount.combine(
                    local_range(first_block, first_lo, CHILD_INDEX_FANOUT),
                    block_range(first_block + 1u, last_block, active_blocks)),
                local_range(last_block, 0u, last_hi));
        }
        index = range.x == target ? range.y : 0u;
    }
    hir_semantic_child_index[row] = index;
}
