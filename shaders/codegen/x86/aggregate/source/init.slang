// Seed aggregate-source pointer jumping.
//
// Each HIR row publishes one outgoing dependency and the field offset carried
// by that edge. Repeated source/step dispatches compose the relation in
// parallel; instruction counting and emission consume the terminal node and
// cumulative offset instead of walking a member chain per copy site.

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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_struct_access_record;

RWStructuredBuffer<uint> x86_aggregate_source_node_out;
RWStructuredBuffer<uint> x86_aggregate_source_offset_out;

static const uint INVALID = 0xffffffffu;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_STRUCT_ACCESS_MEMBER = 1u;
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

uint struct_access_word(uint node, uint slot)
{
    uint row = node * X86_STRUCT_ACCESS_STRIDE + slot;
    return node < gParams.n_hir_nodes ? x86_struct_access_record[row] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(tid);
    if (!valid_node(node))
        return;

    uint info = struct_access_word(node, 2u);
    uint access_kind = info == INVALID ? 0u : info & X86_STRUCT_ACCESS_KIND_MASK;
    uint receiver = struct_access_word(node, 0u);
    uint offset = struct_access_word(node, 1u);
    if (hir_kind[node] == HIR_MEMBER_EXPR &&
        access_kind == X86_STRUCT_ACCESS_MEMBER &&
        valid_node(receiver) && offset != INVALID)
    {
        x86_aggregate_source_node_out[node] = receiver;
        x86_aggregate_source_offset_out[node] = offset;
        return;
    }

    // A semantic name row is already the terminal storage identity. Following
    // its legacy expression-resolution edge can escape through a forwarding
    // grammar wrapper into the surrounding binary/assignment result root.
    // Aggregate-source composition must retain the declaration-bearing name.
    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        x86_aggregate_source_node_out[node] = node;
        x86_aggregate_source_offset_out[node] = 0u;
        return;
    }

    uint resolved = x86_expr_resolved_node[node];
    x86_aggregate_source_node_out[node] = valid_node(resolved) ? resolved : node;
    x86_aggregate_source_offset_out[node] = 0u;
}
