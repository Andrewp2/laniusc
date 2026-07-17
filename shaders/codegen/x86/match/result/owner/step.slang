// Pointer-jump nearest match-arm result ownership.

import gpu_index;
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
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> x86_match_result_owner_in;
StructuredBuffer<uint> x86_match_result_owner_link_in;

RWStructuredBuffer<uint> x86_match_result_owner_out;
RWStructuredBuffer<uint> x86_match_result_owner_link_out;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
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

    uint owner = x86_match_result_owner_in[node];
    if (valid_node(owner))
    {
        x86_match_result_owner_out[node] = owner;
        x86_match_result_owner_link_out[node] = INVALID;
        return;
    }

    uint link = x86_match_result_owner_link_in[node];
    if (!valid_node(link) || link == node)
    {
        x86_match_result_owner_out[node] = INVALID;
        x86_match_result_owner_link_out[node] = INVALID;
        return;
    }

    uint ancestor_owner = x86_match_result_owner_in[link];
    if (valid_node(ancestor_owner))
    {
        x86_match_result_owner_out[node] = ancestor_owner;
        x86_match_result_owner_link_out[node] = INVALID;
        return;
    }

    uint next_link = x86_match_result_owner_link_in[link];
    x86_match_result_owner_out[node] = INVALID;
    x86_match_result_owner_link_out[node] = valid_node(next_link) ? next_link : INVALID;
}
