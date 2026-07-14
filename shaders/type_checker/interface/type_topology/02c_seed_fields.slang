// Seed public aggregate field type roots in parallel over HIR rows.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(hir_status[5u], gParams.hir_capacity); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint field = linear_thread_id(dtid);
    if (field >= active_hir_count())
        return;
    uint aggregate = hir_struct_field_parent_struct[field];
    uint owner = aggregate < gParams.hir_capacity ? public_decl_index_by_hir[aggregate] : INVALID;
    if (owner >= gParams.decl_capacity)
        return;
    uint type_node = hir_struct_field_type_node[field];
    if (type_node >= active_hir_count() || hir_kind[type_node] != HIR_TYPE ||
        interface_type_parent[type_node] != INVALID)
    {
        atomic_u32_or(interface_status, 0u, 256u);
        atomic_u32_min(interface_status, 1u, type_node);
        return;
    }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, type_node, INVALID, owner);
    if (prior != INVALID && prior != owner)
    {
        atomic_u32_or(interface_status, 0u, 256u);
        atomic_u32_min(interface_status, 1u, type_node);
    }
}
