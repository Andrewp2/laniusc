// Scatter one direct child relation per reachable non-root type. Generic
// argument ranks and unary ordinal zero make the result deterministic without
// an in-shader child walk or atomic append order.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_parent;
StructuredBuffer<uint> interface_type_child_ordinal;
StructuredBuffer<uint> interface_type_index_by_hir;
StructuredBuffer<uint> interface_type_edge_prefix;
StructuredBuffer<uint> interface_type_edge_count;
RWStructuredBuffer<uint> interface_type_edges;
RWStructuredBuffer<uint> interface_type_edge_written;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    uint child_index = interface_type_index_by_hir[node];
    uint parent = interface_type_parent[node];
    if (child_index == INVALID || parent == INVALID)
        return;
    uint count = min(interface_type_count[0u], gParams.hir_capacity);
    uint parent_index = parent < gParams.hir_capacity
                            ? interface_type_index_by_hir[parent]
                            : INVALID;
    uint ordinal = interface_type_child_ordinal[node];
    if (child_index >= count || parent_index >= count || child_index >= parent_index ||
        ordinal >= interface_type_edge_count[parent_index])
    {
        atomic_u32_or(interface_status, 0u, 1024u);
        atomic_u32_min(interface_status, 1u, node);
        return;
    }
    uint destination = interface_type_edge_prefix[parent_index] + ordinal;
    if (destination >= gParams.hir_capacity)
    {
        atomic_u32_or(interface_status, 0u, 1024u);
        atomic_u32_min(interface_status, 1u, node);
        return;
    }
    interface_type_edges[destination] = child_index;
    interface_type_edge_written[destination] = 1u;
}
