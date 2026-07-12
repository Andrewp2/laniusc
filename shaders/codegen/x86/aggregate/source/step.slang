// Compose aggregate-source dependencies by pointer jumping.
// Each dispatch doubles the member/resolution chain span represented per row.

import gpu_index;

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
StructuredBuffer<uint> x86_aggregate_source_node_in;
StructuredBuffer<uint> x86_aggregate_source_offset_in;

RWStructuredBuffer<uint> x86_aggregate_source_node_out;
RWStructuredBuffer<uint> x86_aggregate_source_offset_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 tid)
{
    return tid.x + tid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(tid);
    if (!valid_node(node))
        return;

    uint link = x86_aggregate_source_node_in[node];
    uint own_offset = x86_aggregate_source_offset_in[node];
    if (!valid_node(link))
    {
        x86_aggregate_source_node_out[node] = INVALID;
        x86_aggregate_source_offset_out[node] = own_offset;
        return;
    }

    uint next = x86_aggregate_source_node_in[link];
    uint next_offset = x86_aggregate_source_offset_in[link];
    if (own_offset == INVALID || next_offset == INVALID ||
        own_offset > (INVALID - 1u) - next_offset)
    {
        x86_aggregate_source_node_out[node] = INVALID;
        x86_aggregate_source_offset_out[node] = INVALID;
        return;
    }
    x86_aggregate_source_node_out[node] = valid_node(next) ? next : INVALID;
    x86_aggregate_source_offset_out[node] = own_offset + next_offset;
}
