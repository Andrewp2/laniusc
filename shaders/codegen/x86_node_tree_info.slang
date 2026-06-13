// x86_64 backend HIR tree projection.
//
// Pareas codegen operates over node-property arrays. The parser already owns
// the full tree buffers. HIR nodes are in preorder, so parent plus subtree_end
// is enough for later passes to derive first-child and next-sibling links
// without retaining a duplicate backend tree record.

import gpu_index;
import status;
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
StructuredBuffer<uint> subtree_end;

RWStructuredBuffer<uint> x86_node_tree_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
// Host diagnostics treat this detail as a HIR node; keep it distinct from
// token-addressed call-ABI errors.
static const uint X86_ERR_TREE_SHAPE = 57u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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

void publish_error(uint node)
{
    publish_stage_error_min_detail4(x86_node_tree_status, X86_ERR_TREE_SHAPE, node);
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
    uint end = subtree_end[node];
    uint parent_end = valid_node(p) ? subtree_end[p] : active_nodes;
    bool end_in_active_tree = valid_node(end) || end == active_nodes;
    bool parent_end_in_active_tree = valid_node(parent_end) || parent_end == active_nodes;
    bool parent_precedes_node = p == INVALID || p < node;
    bool node_range_is_nonempty = end > node;
    bool node_range_is_in_parent =
        p == INVALID ||
        (parent_end_in_active_tree && parent_end > node && end <= parent_end);
    bool ok = p != node &&
              parent_precedes_node &&
              end_in_active_tree &&
              node_range_is_nonempty &&
              node_range_is_in_parent;
    if (!ok)
    {
        publish_error(node);
        return;
    }
}
