// x86_64 owning-function assignment pointer-jump step.
//
// This is the Slang form of Pareas' bulk linked-list pointer jumping. Each
// dispatch doubles the known parent-chain span and carries the nearest function
// owner found so far. Downstream backend stages consume the finalized
// `x86_node_func` owner array instead of walking ancestors locally.

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
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_func_owner_link_in;
StructuredBuffer<uint> x86_node_func_in;

RWStructuredBuffer<uint> x86_func_owner_link_out;
RWStructuredBuffer<uint> x86_node_func_out;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_NODE_TREE_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node_i)
{
    return node_i != INVALID && node_i < active_hir_node_count();
}

bool node_tree_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (!node_tree_ok() || node_i >= active_hir_node_count())
    {
        if (node_i < gParams.n_hir_nodes)
        {
            x86_node_func_out[node_i] = INVALID;
            x86_func_owner_link_out[node_i] = INVALID;
        }
        return;
    }

    uint link = x86_func_owner_link_in[node_i];
    uint owner = x86_node_func_in[node_i];
    uint ancestor_owner = valid_node(link) ? x86_node_func_in[link] : INVALID;
    uint ancestor_link = valid_node(link) ? x86_func_owner_link_in[link] : INVALID;

    x86_node_func_out[node_i] = pareas_valid_link(owner) ? owner : ancestor_owner;
    x86_func_owner_link_out[node_i] = valid_node(link) ? ancestor_link : INVALID;
}
