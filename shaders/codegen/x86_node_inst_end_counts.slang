// x86_64 node instruction postorder bucket counts.
//
// Instruction-producing HIR nodes are ordered by the backend tree key
// (subtree_end ascending, node rank descending). This pass builds the
// subtree_end histogram that the following scan/order passes use to place
// nodes without pairwise comparisons.

import gpu_index;
import scatter;
struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_tree_subtree_end;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_node_inst_count_info;
StructuredBuffer<uint> x86_node_inst_count_payload;
StructuredBuffer<uint> x86_node_inst_count_status;

RWStructuredBuffer<uint> x86_node_inst_scan_input;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_NODE_INST_COUNTS_OK = 1u;
static const uint X86_NODE_INST_COUNT_STRIDE = 2u;
static const uint X86_NODE_INST_COUNT_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_COUNT_COUNT_MASK = 0x0fffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool upstream_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u &&
           x86_node_inst_count_status[0u] == X86_NODE_INST_COUNTS_OK &&
           x86_node_inst_count_status[1u] == 0u;
}

uint node_inst_count_word(uint node, uint field)
{
    if (node >= active_hir_node_count())
        return INVALID;
    if (field == 0u)
        return x86_node_inst_count_info[node];
    if (field == 1u)
        return x86_node_inst_count_payload[node];
    return INVALID;
}

uint4 node_inst_count_record(uint node)
{
    uint info = node_inst_count_word(node, 0u);
    uint payload = node_inst_count_word(node, 1u);
    uint count = info == INVALID ? INVALID : info & X86_NODE_INST_COUNT_COUNT_MASK;
    uint kind = info == INVALID ? INVALID : info >> X86_NODE_INST_COUNT_KIND_SHIFT;
    return uint4(node, count, kind, payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint n = active_hir_node_count();
    if (!upstream_ok() || node >= n)
        return;

    uint4 count = node_inst_count_record(node);
    if (count.x != node || count.y == 0u || count.y == INVALID)
        return;

    uint end = x86_tree_subtree_end[node];
    if (end <= n)
        atomic_counter_add(x86_node_inst_scan_input, end, 1u);
}
