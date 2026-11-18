// Publish pointer-jumped call-argument owners and ordinals.
//
// The pass runs over the call argument list (hir_list_rank_node) that the
// argument links pass marked; other rows are not read or written.

import shared.buffers.atomics;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirCall;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_call_arg_owner_a;
StructuredBuffer<uint> hir_call_arg_rank_a;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;

RWStructuredBuffer<uint> hir_call_arg_parent_call;
RWStructuredBuffer<uint> hir_call_arg_ordinal;
RWStructuredBuffer<uint> hir_call_arg_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirCall.uses_status_count != 0u ? min(gHirCall.n, tree_count_status[5u]) : gHirCall.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= hir_list_rank_count[0u])
        return;
    uint node = hir_list_rank_node[row];
    if (!valid_node(node))
        return;

    uint call_node = hir_call_arg_owner_a[node];
    if (!valid_node(call_node))
        return;

    uint ordinal = hir_call_arg_rank_a[node];
    hir_call_arg_parent_call[node] = call_node;
    hir_call_arg_ordinal[node] = ordinal;
    atomic_u32_max(hir_call_arg_count, call_node, ordinal + 1u);
}
