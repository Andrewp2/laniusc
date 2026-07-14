// Emit synthetic function and nominal signature records after all HIR-backed
// children and the shared void leaf.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_signature_type_flag;
StructuredBuffer<uint> interface_signature_type_prefix;
StructuredBuffer<uint> interface_signature_edge_count;
StructuredBuffer<uint> interface_signature_edge_prefix;
RWStructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_status;
static const uint TYPE_WORDS = 9u;
static const uint TYPE_KIND_DECLARATION = 3u;
static const uint TYPE_KIND_FUNCTION = 7u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, detail); }
void write_type(uint index, uint kind, uint lo, uint hi, uint first_edge, uint edge_count, uint nominal_unit)
{
    uint base = index * TYPE_WORDS;
    interface_types[base + 0u] = kind; interface_types[base + 1u] = lo;
    interface_types[base + 2u] = hi; interface_types[base + 3u] = first_edge;
    interface_types[base + 4u] = edge_count; interface_types[base + 5u] = 0u;
    interface_types[base + 6u] = 0u; interface_types[base + 7u] = 0u;
    interface_types[base + 8u] = nominal_unit;
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint persisted = linear_thread_id(dtid);
    uint public_count = min(public_decl_count[0u], gParams.decl_capacity);
    if (persisted >= public_count || interface_signature_type_flag[persisted] == 0u)
        return;
    uint local = public_decl_local_id[persisted];
    if (local >= gParams.decl_capacity) { fail(persisted); return; }
    uint kind = decl_kind[local];
    uint hir_count = min(interface_type_count[0u], gParams.hir_capacity);
    uint type_index = hir_count + 1u + interface_signature_type_prefix[persisted];
    uint first_edge = interface_type_edge_total[0u] + interface_signature_edge_prefix[persisted];
    uint edge_count = interface_signature_edge_count[persisted];
    if (kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN ||
        kind == HIR_ITEM_KIND_ENUM_VARIANT)
        write_type(type_index, TYPE_KIND_FUNCTION, 0u, 0u, first_edge, edge_count, 0u);
    else
    {
        uint nominal = persisted;
        if (kind != HIR_ITEM_KIND_STRUCT && kind != HIR_ITEM_KIND_ENUM)
        { fail(persisted); return; }
        if (nominal >= public_count) { fail(persisted); return; }
        write_type(type_index, TYPE_KIND_DECLARATION, gParams.library_id, nominal, 0u, 0u, gParams.unit_id);
    }
    interface_signature_type_by_decl[persisted] = type_index;
}
