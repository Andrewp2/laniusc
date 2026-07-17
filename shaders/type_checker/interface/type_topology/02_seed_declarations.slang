// Seed direct dense type roots owned by public functions, constants, and aliases.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint> compact_const_type;
RWStructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_decl_direct_type_hir;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(compact_hir_count[0u], gParams.hir_capacity); }
bool type_node(uint node) { return node < active_hir_count() && compact_hir_core[node].kind == HIR_TYPE; }
void seed(uint type_node_id, uint owner)
{
    if (!type_node(type_node_id) || interface_type_parent[type_node_id] != INVALID)
    {
        atomic_u32_or(interface_status, 0u, 256u);
        atomic_u32_min(interface_status, 1u, owner);
        return;
    }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, type_node_id, INVALID, owner);
    if (prior != INVALID && prior != owner)
    {
        atomic_u32_or(interface_status, 0u, 256u);
        atomic_u32_min(interface_status, 1u, type_node_id);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint persisted = linear_thread_id(dtid);
    if (persisted >= min(public_decl_count[0u], gParams.decl_capacity)) return;
    interface_decl_direct_type_hir[persisted] = INVALID;
    uint local = public_decl_local_id[persisted];
    if (local >= gParams.decl_capacity) return;
    uint kind = decl_kind[local];
    if (kind != HIR_ITEM_KIND_FN && kind != HIR_ITEM_KIND_EXTERN_FN &&
        kind != HIR_ITEM_KIND_CONST && kind != HIR_ITEM_KIND_TYPE_ALIAS) return;
    uint hir = decl_hir_node[local];
    if (hir >= active_hir_count()) return;
    uint direct = kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN
        ? compact_fn_return_type[hir]
        : kind == HIR_ITEM_KIND_CONST
            ? compact_const_type[hir]
            : compact_type_alias_target[hir];
    if ((kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN) && direct == INVALID) return;
    interface_decl_direct_type_hir[persisted] = direct;
    seed(direct, persisted);
}
