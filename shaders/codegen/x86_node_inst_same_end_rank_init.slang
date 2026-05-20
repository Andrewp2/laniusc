// x86_64 node instruction same-subtree-end rank seed.
//
// Pareas builds execution order from tree arrays with bulk pointer operations.
// This pass seeds one linked-list forest per subtree_end bucket: each
// instruction-producing node points at its same-end parent, and its rank starts
// with whether that parent also produces an instruction. Pointer-jump steps then
// turn the seed into the same-end ancestor count used by node_inst_order.

import gpu_index;
import tree_pareas;

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
StructuredBuffer<uint> x86_node_inst_count_record;
StructuredBuffer<uint> x86_node_inst_count_status;

RWStructuredBuffer<uint> x86_node_inst_same_end_link;
RWStructuredBuffer<uint> x86_node_inst_same_end_rank;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_NODE_INST_COUNTS_OK = 1u;
static const uint X86_NODE_INST_COUNT_STRIDE = 3u;
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

uint node_inst_count_word(uint node, uint field)
{
    return row_major_load<uint>(
        x86_node_inst_count_record,
        node,
        X86_NODE_INST_COUNT_STRIDE,
        field,
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

bool produces_instruction(uint node)
{
    if (!valid_node(node))
        return false;
    uint4 count = node_inst_count_record(node);
    return count.x == node && count.y != 0u && count.y != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!upstream_ok() || node >= active_hir_node_count())
    {
        if (node < gParams.n_hir_nodes)
        {
            x86_node_inst_same_end_link[node] = INVALID;
            x86_node_inst_same_end_rank[node] = 0u;
        }
        return;
    }

    uint end = x86_node_tree_record[node].w;
    uint parent = x86_node_tree_record[node].x;
    bool same_end_parent = valid_node(parent) && x86_node_tree_record[parent].w == end;
    x86_node_inst_same_end_link[node] = same_end_parent ? parent : INVALID;
    x86_node_inst_same_end_rank[node] =
        same_end_parent && produces_instruction(parent) ? 1u : 0u;
}
