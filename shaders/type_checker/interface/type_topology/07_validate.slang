// Validate the topological invariant after scatter has completed.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_hir_order;
StructuredBuffer<uint> interface_type_parent;
StructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = linear_thread_id(dtid);
    uint count = min(interface_type_count[0u], gParams.hir_capacity);
    if (index >= count)
        return;
    uint node = interface_type_hir_order[index];
    if (node >= gParams.hir_capacity || interface_type_index_by_hir[node] != index)
    {
        atomic_u32_or(interface_status, 0u, 512u);
        atomic_u32_min(interface_status, 1u, index);
        return;
    }
    uint parent = interface_type_parent[node];
    if (parent == INVALID)
        return;
    uint parent_index = parent < gParams.hir_capacity
                            ? interface_type_index_by_hir[parent]
                            : INVALID;
    if (parent_index == INVALID || parent_index <= index)
    {
        atomic_u32_or(interface_status, 0u, 512u);
        atomic_u32_min(interface_status, 1u, index);
    }
}
