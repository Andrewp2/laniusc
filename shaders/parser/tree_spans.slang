// Parallel preorder subtree navigation recovery.
//
// For each production node, compute:
// - first_child: first child node index, or INVALID
// - subtree_end: exclusive end index for this node's subtree
// - next_sibling: sibling following this subtree, or INVALID
//
// The prefix stage computes E[p] = sum_{k < p}(1 - arity[k]). The exclusive
// subtree end for node i is the first prefix position p > i where
// E[p] >= E[i] + 1. A max segment tree over prefix-block maxima locates the
// first candidate block in logarithmic work, then the pass scans only that
// block to recover the exact prefix position.

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_prefix_blocks;
    uint max_tree_leaf_base;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> prod_arity;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<int> tree_prefix;
StructuredBuffer<int> prefix_block_max;
StructuredBuffer<int> prefix_block_max_tree;

RWStructuredBuffer<uint> first_child;
RWStructuredBuffer<uint> next_sibling;
RWStructuredBuffer<uint> subtree_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_SEARCH_STACK = 64u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gTree.uses_ll1 != 0u ? min(gTree.n, ll1_status[5u]) : gTree.n;
}

uint find_next_block_linear(uint lo_block, int target)
{
    uint block_idx = lo_block;
    [loop]
    while (block_idx < gTree.n_prefix_blocks)
    {
        if (prefix_block_max[block_idx] >= target)
            return block_idx;
        block_idx += 1u;
    }
    return INVALID;
}

uint find_next_block(uint lo_block, int target)
{
    if (lo_block >= gTree.n_prefix_blocks || gTree.max_tree_leaf_base == 0u)
        return INVALID;

    uint stack_node[MAX_SEARCH_STACK];
    uint stack_l[MAX_SEARCH_STACK];
    uint stack_r[MAX_SEARCH_STACK];
    uint sp = 0u;

    stack_node[sp] = 1u;
    stack_l[sp] = 0u;
    stack_r[sp] = gTree.max_tree_leaf_base;
    sp += 1u;

    [loop]
    while (sp > 0u)
    {
        sp -= 1u;
        uint node = stack_node[sp];
        uint l = stack_l[sp];
        uint r = stack_r[sp];

        if (r <= lo_block || l >= gTree.n_prefix_blocks)
            continue;

        bool fully_in_range = l >= lo_block;
        if (fully_in_range && prefix_block_max_tree[node] < target)
            continue;

        if (r - l == 1u)
        {
            if (l >= lo_block && l < gTree.n_prefix_blocks && prefix_block_max_tree[node] >= target)
                return l;
            continue;
        }

        if (sp + 2u > MAX_SEARCH_STACK)
            return find_next_block_linear(lo_block, target);

        uint mid = (l + r) >> 1u;

        // Push right first so the left half is popped and searched first.
        stack_node[sp] = node * 2u + 1u;
        stack_l[sp] = mid;
        stack_r[sp] = r;
        sp += 1u;

        stack_node[sp] = node * 2u;
        stack_l[sp] = l;
        stack_r[sp] = mid;
        sp += 1u;
    }

    return INVALID;
}

uint find_subtree_end(uint i, uint n)
{
    int target = tree_prefix[i] + 1;
    uint p = i + 1u;
    uint block_idx = p / WG_SIZE;
    uint block_end = min(n + 1u, (block_idx + 1u) * WG_SIZE);

    [loop]
    while (p < block_end)
    {
        if (tree_prefix[p] >= target)
            return p;
        p += 1u;
    }

    uint candidate_block = find_next_block(block_idx + 1u, target);
    if (candidate_block != INVALID)
    {
        uint start = candidate_block * WG_SIZE;
        uint end = min(n + 1u, start + WG_SIZE);
        uint k = start;
        [loop]
        while (k < end)
        {
            if (tree_prefix[k] >= target)
                return k;
            k += 1u;
        }
    }

    return n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint arity = prod_arity[node_kind[i]];
    first_child[i] = (arity > 0u && i + 1u < n) ? i + 1u : INVALID;

    uint end = find_subtree_end(i, n);
    subtree_end[i] = end;

    next_sibling[i] = (end < n && parent[end] == parent[i]) ? end : INVALID;
}
