// Parallel preorder parent recovery.
//
// The prefix stage computes E[p] = sum_{k < p}(1 - arity[k]). For node i,
// the parent is the nearest previous node j with E[j] >= E[i]. This pass
// searches inside the current 256-prefix block, then uses a max segment tree to
// find the nearest previous candidate block without walking all intervening
// blocks.

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_prefix_blocks;
    uint max_tree_leaf_base;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> emit_stream;
StructuredBuffer<uint> ll1_status;
StructuredBuffer<int> tree_prefix;
StructuredBuffer<int> prefix_block_max;
StructuredBuffer<int> prefix_block_max_tree;

RWStructuredBuffer<uint> node_kind;
RWStructuredBuffer<uint> parent;

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

uint find_previous_block_linear(uint hi_block, int target)
{
    uint block_idx = hi_block;
    [loop]
    while (block_idx > 0u)
    {
        block_idx -= 1u;
        if (prefix_block_max[block_idx] >= target)
            return block_idx;
    }
    return INVALID;
}

uint find_previous_block(uint hi_block, int target)
{
    if (hi_block == 0u || gTree.max_tree_leaf_base == 0u)
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

        if (l >= hi_block || l >= gTree.n_prefix_blocks)
            continue;

        bool fully_in_range = r <= hi_block;
        if (fully_in_range && prefix_block_max_tree[node] < target)
            continue;

        if (r - l == 1u)
        {
            if (l < hi_block && l < gTree.n_prefix_blocks && prefix_block_max_tree[node] >= target)
                return l;
            continue;
        }

        if (sp + 2u > MAX_SEARCH_STACK)
            return find_previous_block_linear(hi_block, target);

        uint mid = (l + r) >> 1u;

        // Push left first so the right half is popped and searched first.
        stack_node[sp] = node * 2u;
        stack_l[sp] = l;
        stack_r[sp] = mid;
        sp += 1u;

        stack_node[sp] = node * 2u + 1u;
        stack_l[sp] = mid;
        stack_r[sp] = r;
        sp += 1u;
    }

    return INVALID;
}

uint find_parent(uint i, uint n)
{
    int target = tree_prefix[i];
    uint block_idx = i / WG_SIZE;
    uint block_start = block_idx * WG_SIZE;
    uint j = i;

    [loop]
    while (j > block_start)
    {
        j -= 1u;
        if (tree_prefix[j] >= target)
            return j;
    }

    uint candidate_block = find_previous_block(block_idx, target);
    if (candidate_block != INVALID)
    {
        uint start = candidate_block * WG_SIZE;
        uint end = min(n, start + WG_SIZE);
        uint k = end;
        [loop]
        while (k > start)
        {
            k -= 1u;
            if (tree_prefix[k] >= target)
                return k;
        }
    }

    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();

    if (i >= n)
        return;

    uint kind = emit_stream[i];
    node_kind[i] = kind;
    parent[i] = find_parent(i, n);
}
