// Seed public function parameter type roots from compact parameter rows.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
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
void seed(uint type_node_id, uint owner, uint detail)
{
    if (!type_node(type_node_id) || interface_type_parent[type_node_id] != INVALID)
    {
        atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, detail); return;
    }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, type_node_id, INVALID, owner);
    if (prior != INVALID && prior != owner)
    { atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, detail); }
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= min(compact_param_count[0u], gParams.hir_capacity)) return;
    HirParam param = compact_params[row];
    uint owner = param.owner < active_hir_count() ? public_decl_index_by_hir[param.owner] : INVALID;
    if (owner < gParams.decl_capacity) seed(param.type_node, owner, row);
}
