// Seed direct type roots owned by public functions, constants, and aliases.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> hir_type_alias_target_node;
StructuredBuffer<uint> hir_stmt_record;
RWStructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_decl_direct_type_hir;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(hir_status[5u], gParams.hir_capacity); }

void seed(uint type_node, uint owner)
{
    if (type_node >= active_hir_count() || hir_kind[type_node] != HIR_TYPE)
    {
        atomic_u32_or(interface_status, 0u, 256u);
        atomic_u32_min(interface_status, 1u, owner);
        return;
    }
    if (interface_type_parent[type_node] != INVALID)
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint persisted = linear_thread_id(dtid);
    if (persisted >= min(public_decl_count[0u], gParams.decl_capacity))
        return;
    uint local = public_decl_local_id[persisted];
    interface_decl_direct_type_hir[persisted] = INVALID;
    if (local >= gParams.decl_capacity)
        return;
    uint hir = decl_hir_node[local];
    if (hir >= gParams.hir_capacity)
        return;
    uint kind = decl_kind[local];
    if (kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN)
    {
        uint return_type = hir_fn_return_type_node[hir];
        // An omitted return annotation is a valid implicit-void signature and
        // has no parser HIR type node to add to this forest.
        if (return_type != INVALID)
        {
            interface_decl_direct_type_hir[persisted] = return_type;
            seed(return_type, persisted);
        }
    }
    else if (kind == HIR_ITEM_KIND_CONST)
    {
        uint type_node = hir_stmt_record[hir * STMT_RECORD_STRIDE + 3u];
        interface_decl_direct_type_hir[persisted] = type_node;
        seed(type_node, persisted);
    }
    else if (kind == HIR_ITEM_KIND_TYPE_ALIAS)
    {
        uint type_node = hir_type_alias_target_node[hir];
        interface_decl_direct_type_hir[persisted] = type_node;
        seed(type_node, persisted);
    }
}
