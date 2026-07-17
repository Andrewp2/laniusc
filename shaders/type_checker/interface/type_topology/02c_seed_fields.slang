// Seed public aggregate field type roots from compact field-family rows.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 d) { return d.x + d.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(compact_hir_count[0u], gParams.hir_capacity); }
bool type_node(uint node) { return node < active_hir_count() && compact_hir_core[node].kind == HIR_TYPE; }
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= min(compact_field_count[0u], gParams.hir_capacity)) return;
    HirField field = compact_fields[row];
    uint owner = field.owner < active_hir_count() ? public_decl_index_by_hir[field.owner] : INVALID;
    if (owner >= gParams.decl_capacity) return;
    if (!type_node(field.value) || interface_type_parent[field.value] != INVALID)
    { atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, row); return; }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, field.value, INVALID, owner);
    if (prior != INVALID && prior != owner)
    { atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, row); }
}
