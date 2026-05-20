// x86_64 backend HIR tree projection.
//
// Pareas codegen operates over node-property arrays: parent, child/sibling
// links, subtree spans, and node data. The parser already owns the tree buffers,
// but the x86 backend needs a stable attributed tree record so later
// instruction counting and generation consume backend records instead of
// reconstructing tree shape locally in each pass.

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
    bool ok = p != node && (valid_node(end) || end == active_nodes);
    if (!ok)
    {
        x86_node_tree_record[node] = uint4(INVALID, INVALID, INVALID, INVALID);
        publish_error(node);
        return;
    }

    uint next = next_sibling[node];
    uint child = first_child[node];
    x86_node_tree_record[node] = uint4(
        p,
        valid_node(child) ? child : INVALID,
        valid_node(next) ? next : INVALID,
        end);
}
