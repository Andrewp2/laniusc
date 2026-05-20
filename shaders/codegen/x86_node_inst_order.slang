// x86_64 node instruction execution ordering.
//
// HIR nodes are stored in tree preorder, but executable value instructions need
// descendants before their parents. This pass ranks each active node by a
// postorder-style key derived from parser tree records, then writes the
// node-local instruction counts into that order for the prefix scan.
//
// x86_node_inst_count_status[3] is the compact row count for nodes with
// nonzero local instruction counts. It is not the summed instruction total; the
// following prefix scan computes that from x86_node_inst_scan_input.

import gpu_index;
import prefix_scan;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> x86_node_tree_record;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_node_inst_count_record;
StructuredBuffer<uint> x86_node_inst_count_status;
StructuredBuffer<uint> x86_node_inst_same_end_rank;
StructuredBuffer<uint> x86_node_inst_scan_local_prefix;
StructuredBuffer<uint> x86_node_inst_scan_block_prefix;

RWStructuredBuffer<uint> x86_node_inst_order_record;
RWStructuredBuffer<uint> x86_node_inst_same_end_bucket_count;
RWStructuredBuffer<uint4> x86_node_inst_subtree_slot_bounds;
RWStructuredBuffer<uint> x86_node_inst_scan_input;
RWStructuredBuffer<uint> x86_node_inst_order_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_NODE_INST_COUNTS_OK = 1u;
static const uint X86_NODE_INST_ORDER_OK = 1u;
static const uint X86_ERR_NODE_INST_ORDER = 12u;
static const uint WG_SIZE = 256u;
static const uint X86_NODE_INST_COUNT_STRIDE = 3u;
static const uint X86_NODE_INST_COUNT_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_COUNT_COUNT_MASK = 0x0fffffffu;
static const uint X86_NODE_INST_ORDER_STRIDE = 3u;
static const uint X86_NODE_INST_ORDER_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_ORDER_COUNT_MASK = 0x0fffffffu;

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

bool upstream_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u &&
           x86_node_inst_count_status[0u] == X86_NODE_INST_COUNTS_OK &&
           x86_node_inst_count_status[1u] == 0u;
}

bool compact_order_count_ok(uint active_nodes)
{
    return x86_node_inst_count_status[3u] <= min(active_nodes, gParams.inst_capacity);
}

uint scanned_prefix_for_index(uint index)
{
    return global_exclusive_prefix(
        index,
        WG_SIZE,
        x86_node_inst_scan_local_prefix,
        x86_node_inst_scan_block_prefix);
}

uint bucket_count_for_end(uint end, uint compact_order_count, uint active_nodes)
{
    uint base = scanned_prefix_for_index(end);
    uint next_base = end < active_nodes ? scanned_prefix_for_index(end + 1u) : compact_order_count;
    return next_base >= base ? next_base - base : 0u;
}

uint execution_slot_for_node(uint node, uint active_nodes)
{
    uint end = x86_node_tree_record[node].w;
    uint compact_order_count = x86_node_inst_count_status[3u];
    uint base = scanned_prefix_for_index(end);
    uint bucket_count = bucket_count_for_end(end, compact_order_count, active_nodes);
    uint ancestor_count = x86_node_inst_same_end_rank[node];
    if (bucket_count == 0u || ancestor_count >= bucket_count)
        return INVALID;
    return base + bucket_count - 1u - ancestor_count;
}

uint first_slot_for_subtree(uint node, uint active_nodes)
{
    return scanned_prefix_for_index(min(node + 1u, active_nodes));
}

uint after_slot_for_subtree(uint node, uint active_nodes)
{
    uint end = x86_node_tree_record[node].w;
    if (end == INVALID || end <= node || end > active_nodes)
        return INVALID;

    uint compact_order_count = x86_node_inst_count_status[3u];
    uint base = scanned_prefix_for_index(end);
    uint bucket_count = bucket_count_for_end(end, compact_order_count, active_nodes);
    uint ancestor_count = x86_node_inst_same_end_rank[node];
    if (ancestor_count > bucket_count)
        return INVALID;
    return base + bucket_count - ancestor_count;
}

uint node_inst_count_word(uint node, uint slot)
{
    return row_major_load<uint>(
        x86_node_inst_count_record,
        node,
        X86_NODE_INST_COUNT_STRIDE,
        slot,
        INVALID);
}

uint4 node_inst_count_record(uint node)
{
    uint id = node_inst_count_word(node, 0u);
    uint info = node_inst_count_word(node, 1u);
    uint payload = node_inst_count_word(node, 2u);
    uint count = info == INVALID ? INVALID : info & X86_NODE_INST_COUNT_COUNT_MASK;
    uint kind = info == INVALID ? INVALID : info >> X86_NODE_INST_COUNT_KIND_SHIFT;
    return uint4(id, count, kind, payload);
}

void publish_error(uint detail)
{
    publish_stage_error_min_detail4(
        x86_node_inst_order_status,
        X86_ERR_NODE_INST_ORDER,
        detail);
}

uint pack_order_info(uint count, uint kind)
{
    if (count > X86_NODE_INST_ORDER_COUNT_MASK)
        return INVALID;
    return (kind << X86_NODE_INST_ORDER_KIND_SHIFT) |
           (count & X86_NODE_INST_ORDER_COUNT_MASK);
}

bool write_order_record(uint slot, uint4 count)
{
    uint info = pack_order_info(count.y, count.z);
    if (info == INVALID)
        return false;
    row_major_store<uint>(
        x86_node_inst_order_record,
        slot,
        X86_NODE_INST_ORDER_STRIDE,
        0u,
        count.x);
    row_major_store<uint>(
        x86_node_inst_order_record,
        slot,
        X86_NODE_INST_ORDER_STRIDE,
        1u,
        info);
    row_major_store<uint>(
        x86_node_inst_order_record,
        slot,
        X86_NODE_INST_ORDER_STRIDE,
        2u,
        count.w);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint n = active_hir_node_count();
    bool ok = upstream_ok() && compact_order_count_ok(n);
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
        x86_node_inst_order_status[3u] = ok ? x86_node_inst_count_status[3u] : 0u;
        uint order_count = ok ? x86_node_inst_count_status[3u] : 0u;
        if (order_count <= n)
            x86_node_inst_scan_input[order_count] = 0u;
    }

    if (!ok || !valid_node(node))
        return;

    uint first_slot = first_slot_for_subtree(node, n);
    uint after_slot = after_slot_for_subtree(node, n);
    x86_node_inst_subtree_slot_bounds[node] =
        (after_slot != INVALID && after_slot >= first_slot)
            ? uint4(first_slot, after_slot, x86_node_tree_record[node].w, 0u)
            : uint4(INVALID, INVALID, x86_node_tree_record[node].w, 0u);

    uint4 count = node_inst_count_record(node);
    if (count.x != node || count.y == INVALID)
    {
        publish_error(node);
        return;
    }
    if (count.y == 0u)
    {
        x86_node_inst_same_end_bucket_count[node] = 0u;
        return;
    }

    uint slot = execution_slot_for_node(node, n);
    uint compact_order_count = x86_node_inst_count_status[3u];
    if (slot == INVALID || slot >= compact_order_count)
    {
        publish_error(node);
        return;
    }

    if (!write_order_record(slot, count))
    {
        publish_error(node);
        return;
    }
    x86_node_inst_same_end_bucket_count[node] = bucket_count_for_end(
        x86_node_tree_record[node].w,
        compact_order_count,
        n);
    x86_node_inst_scan_input[slot] = count.y;
}
