// x86_64 node instruction execution ordering.
//
// HIR nodes are stored in tree preorder, but executable value instructions need
// descendants before their parents. This pass ranks each active node by a
// postorder-style key derived from parser tree records, then writes the
// node-local instruction counts into that order for the prefix scan.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> x86_node_tree_record;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint4> x86_node_inst_count_record;
StructuredBuffer<uint> x86_node_inst_count_status;

RWStructuredBuffer<uint4> x86_node_inst_order_record;
RWStructuredBuffer<uint> x86_node_inst_order_node;
RWStructuredBuffer<uint> x86_node_inst_order_slot;
RWStructuredBuffer<uint> x86_node_inst_scan_input;
RWStructuredBuffer<uint> x86_node_inst_order_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_NODE_INST_COUNTS_OK = 1u;
static const uint X86_NODE_INST_ORDER_OK = 1u;
static const uint X86_ERR_NODE_INST_ORDER = 12u;

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

bool upstream_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u &&
           x86_node_inst_count_status[0u] == X86_NODE_INST_COUNTS_OK &&
           x86_node_inst_count_status[1u] == 0u;
}

bool node_before(uint lhs, uint rhs)
{
    uint4 lhs_tree = x86_node_tree_record[lhs];
    uint4 rhs_tree = x86_node_tree_record[rhs];
    uint lhs_end = lhs_tree.w;
    uint rhs_end = rhs_tree.w;
    uint lhs_depth = lhs_tree.y;
    uint rhs_depth = rhs_tree.y;

    if (lhs_end != rhs_end)
        return lhs_end < rhs_end;
    if (lhs_depth != rhs_depth)
        return lhs_depth > rhs_depth;
    return lhs < rhs;
}

uint execution_slot_for_node(uint node)
{
    uint rank = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint other = 0u; other < gParams.n_hir_nodes; other += 1u)
    {
        if (other >= n)
            break;
        if (other != node && node_before(other, node))
            rank += 1u;
    }
    return rank;
}

void publish_error(uint detail)
{
    x86_node_inst_order_status[0u] = 0u;
    uint old_error = 0u;
    InterlockedCompareExchange(
        x86_node_inst_order_status[1u],
        0u,
        X86_ERR_NODE_INST_ORDER,
        old_error);
    uint old_detail = INVALID;
    InterlockedMin(x86_node_inst_order_status[2u], detail, old_detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint n = active_hir_node_count();
    bool ok = upstream_ok();
    if (node == 0u)
    {
        x86_node_inst_order_status[0u] = ok ? X86_NODE_INST_ORDER_OK : 0u;
        x86_node_inst_order_status[1u] = ok ? 0u :
                                          (x86_node_inst_count_status[1u] == 0u ?
                                           X86_ERR_NODE_INST_ORDER :
                                           x86_node_inst_count_status[1u]);
        x86_node_inst_order_status[2u] = ok ? INVALID :
                                          (x86_node_inst_count_status[1u] == 0u ?
                                           0u :
                                           x86_node_inst_count_status[2u]);
        x86_node_inst_order_status[3u] = ok ? n : 0u;
    }

    if (!ok || !valid_node(node))
        return;

    uint4 count = x86_node_inst_count_record[node];
    if (count.x != node || count.y == INVALID)
    {
        publish_error(node);
        return;
    }

    uint slot = execution_slot_for_node(node);
    if (slot >= n)
    {
        publish_error(node);
        return;
    }

    x86_node_inst_order_record[slot] = count;
    x86_node_inst_order_node[slot] = node;
    x86_node_inst_order_slot[node] = slot;
    x86_node_inst_scan_input[slot] = count.y;
}
