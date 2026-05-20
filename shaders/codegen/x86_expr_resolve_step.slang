// x86_64 expression-forward pointer-jump step.
//
// This is the Slang equivalent of Pareas-style link jumping over an array
// relation: every dispatch doubles the known forward-chain distance.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> x86_expr_resolved_node_in;
StructuredBuffer<uint> x86_expr_resolve_link_in;

RWStructuredBuffer<uint> x86_expr_resolved_node_out;
RWStructuredBuffer<uint> x86_expr_resolve_link_out;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint link = x86_expr_resolve_link_in[node];
    if (!valid_node(link) || link == node)
    {
        x86_expr_resolved_node_out[node] = x86_expr_resolved_node_in[node];
        x86_expr_resolve_link_out[node] = INVALID;
        return;
    }

    uint resolved = x86_expr_resolved_node_in[link];
    uint next_link = x86_expr_resolve_link_in[link];
    x86_expr_resolved_node_out[node] = valid_node(resolved) ? resolved : INVALID;
    x86_expr_resolve_link_out[node] = valid_node(next_link) ? next_link : INVALID;
}
