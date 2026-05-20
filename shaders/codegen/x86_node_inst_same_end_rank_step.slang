// x86_64 same-subtree-end rank pointer-jump step.
//
// This is the Slang form of Pareas' repeated linked-list pointer jumping: each
// step skips one power-of-two block of same-end ancestors and accumulates the
// instruction-producing ancestor count.

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
StructuredBuffer<uint> x86_node_inst_same_end_link_in;
StructuredBuffer<uint> x86_node_inst_same_end_rank_in;

RWStructuredBuffer<uint> x86_node_inst_same_end_link_out;
RWStructuredBuffer<uint> x86_node_inst_same_end_rank_out;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node >= active_hir_node_count())
    {
        if (node < gParams.n_hir_nodes)
        {
            x86_node_inst_same_end_link_out[node] = INVALID;
            x86_node_inst_same_end_rank_out[node] = 0u;
        }
        return;
    }

    uint link = x86_node_inst_same_end_link_in[node];
    uint rank = x86_node_inst_same_end_rank_in[node];
    uint ancestor_link = valid_node(link) ? x86_node_inst_same_end_link_in[link] : INVALID;
    uint ancestor_rank = valid_node(link) ? x86_node_inst_same_end_rank_in[link] : 0u;

    uint next_link;
    uint next_rank;
    pareas_linked_prefix_count_step(
        link,
        rank,
        ancestor_link,
        ancestor_rank,
        next_link,
        next_rank);
    x86_node_inst_same_end_link_out[node] = next_link;
    x86_node_inst_same_end_rank_out[node] = next_rank;
}
