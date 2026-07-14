// Select compacted HIR roots for constants and aliases.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> interface_signature_type_flag;
StructuredBuffer<uint> interface_decl_direct_type_hir;
StructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_status;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint persisted = linear_thread_id(dtid);
    if (persisted >= min(public_decl_count[0u], gParams.decl_capacity) ||
        interface_signature_type_flag[persisted] != 0u)
        return;
    uint node = interface_decl_direct_type_hir[persisted];
    uint index = node < gParams.hir_capacity ? interface_type_index_by_hir[node] : 0xffffffffu;
    if (index >= gParams.hir_capacity)
    {
        atomic_u32_or(interface_status, 0u, 4096u);
        atomic_u32_min(interface_status, 1u, persisted);
        return;
    }
    interface_signature_type_by_decl[persisted] = index;
}
