// x86_64 match-pattern owner pointer-jump step.
//
// This is the Slang form of Pareas's logarithmic parent-link propagation:
// unowned nodes inherit the nearest already-known owner from their parent link,
// otherwise they jump to that parent's next link.

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
StructuredBuffer<uint> x86_match_pattern_node_owner_in;
StructuredBuffer<uint> x86_match_pattern_owner_link_in;

RWStructuredBuffer<uint> x86_match_pattern_node_owner_out;
RWStructuredBuffer<uint> x86_match_pattern_owner_link_out;

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
    if (!valid_node(node))
        return;

    uint owner = x86_match_pattern_node_owner_in[node];
    uint link = x86_match_pattern_owner_link_in[node];
    if (valid_node(owner) || !valid_node(link))
    {
        x86_match_pattern_node_owner_out[node] = owner;
        x86_match_pattern_owner_link_out[node] = INVALID;
        return;
    }

    uint linked_owner = x86_match_pattern_node_owner_in[link];
    if (valid_node(linked_owner))
    {
        x86_match_pattern_node_owner_out[node] = linked_owner;
        x86_match_pattern_owner_link_out[node] = INVALID;
        return;
    }

    uint next_link = x86_match_pattern_owner_link_in[link];
    x86_match_pattern_node_owner_out[node] = INVALID;
    x86_match_pattern_owner_link_out[node] =
        valid_node(next_link) && next_link != link ? next_link : INVALID;
}
