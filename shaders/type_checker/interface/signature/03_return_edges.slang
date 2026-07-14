// Scatter explicit return types, or the shared synthesized void leaf, as the
// final edge of every function signature.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_signature_edge_count;
StructuredBuffer<uint> interface_signature_edge_prefix;
StructuredBuffer<uint> interface_decl_direct_type_hir;
StructuredBuffer<uint> interface_type_index_by_hir;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_type_edges;
RWStructuredBuffer<uint> interface_type_edge_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, detail); }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint persisted = linear_thread_id(dtid);
    if (persisted >= min(public_decl_count[0u], gParams.decl_capacity))
        return;
    uint local = public_decl_local_id[persisted];
    uint kind = local < gParams.decl_capacity ? decl_kind[local] : 0u;
    if (kind != HIR_ITEM_KIND_FN && kind != HIR_ITEM_KIND_EXTERN_FN &&
        kind != HIR_ITEM_KIND_ENUM_VARIANT)
        return;
    uint edge_count = interface_signature_edge_count[persisted];
    if (edge_count == 0u)
    {
        fail(persisted);
        return;
    }
    uint target;
    if (kind == HIR_ITEM_KIND_ENUM_VARIANT)
    {
        uint owner_local = decl_parent_type_decl[local];
        uint owner = owner_local < gParams.decl_capacity
                        ? public_decl_index_by_local[owner_local] : INVALID;
        target = owner < gParams.decl_capacity
                    ? interface_signature_type_by_decl[owner] : INVALID;
    }
    else
    {
        uint type_node = interface_decl_direct_type_hir[persisted];
        target = type_node < gParams.hir_capacity
                    ? interface_type_index_by_hir[type_node]
                    : min(interface_type_count[0u], gParams.hir_capacity);
    }
    if (target > gParams.hir_capacity)
    {
        fail(persisted);
        return;
    }
    interface_type_edges[interface_type_edge_total[0u] +
                         interface_signature_edge_prefix[persisted] + edge_count - 1u] = target;
    interface_type_edge_written[interface_type_edge_total[0u] +
                                interface_signature_edge_prefix[persisted] + edge_count - 1u] = 1u;
}
