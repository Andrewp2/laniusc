// x86_64 backend HIR tree projection.
//
// Pareas codegen operates over node-property arrays: parent, depth, child
// index, and node data. The parser already owns the tree buffers, but the x86
// backend needs a stable attributed tree record so later instruction counting
// and generation consume backend records instead of reconstructing tree shape
// locally in each pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> subtree_end;

RWStructuredBuffer<uint4> x86_node_tree_record;
RWStructuredBuffer<uint> x86_node_tree_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_ERR_TREE_SHAPE = 9u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint valid_parent_or_invalid(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

bool compute_depth(uint node, out uint depth)
{
    depth = 0u;
    if (!valid_node(node))
        return false;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 256u; guard += 1u)
    {
        uint p = valid_parent_or_invalid(cur);
        if (p == INVALID)
            return true;
        if (p == cur)
            return false;
        depth += 1u;
        cur = p;
    }
    return false;
}

bool compute_child_index(uint node, uint p, out uint child_index)
{
    child_index = 0u;
    if (!valid_node(node))
        return false;
    if (p == INVALID)
        return true;
    if (!valid_node(p))
        return false;

    uint child = first_child[p];
    [loop]
    for (uint guard = 0u; guard < 512u; guard += 1u)
    {
        if (!valid_node(child) || parent[child] != p)
            return false;
        if (child == node)
            return true;
        child = next_sibling[child];
        child_index += 1u;
    }
    return false;
}

void publish_error(uint node)
{
    uint old_error = 0u;
    InterlockedCompareExchange(x86_node_tree_status[1u], 0u, X86_ERR_TREE_SHAPE, old_error);
    uint old_detail = INVALID;
    InterlockedMin(x86_node_tree_status[2u], node, old_detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint active_nodes = active_hir_node_count();

    if (node == 0u)
        x86_node_tree_status[3u] = active_nodes;

    if (node >= active_nodes)
        return;

    uint p = valid_parent_or_invalid(node);
    uint depth = 0u;
    uint child_index = 0u;
    bool ok = compute_depth(node, depth) && compute_child_index(node, p, child_index);
    if (!ok)
    {
        x86_node_tree_record[node] = uint4(INVALID, INVALID, INVALID, INVALID);
        publish_error(node);
        return;
    }

    uint end = subtree_end[node];
    x86_node_tree_record[node] = uint4(
        p,
        depth,
        child_index,
        valid_node(end) || end == active_nodes ? end : INVALID);
}
