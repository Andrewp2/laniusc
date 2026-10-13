// Seed direct dense type roots owned by public declarations and associated
// methods.  Method signatures are exported as members rather than ordinary
// declarations, but their receiver and return types still belong to the owning
// public type declaration's reachable interface graph.

import hir_records;
import atomics;
import type_checker.interface.method_parameters;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint> compact_const_type;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> interface_implementation_index_by_hir;
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
static const uint TYPE_REF_INSTANCE = 3u;
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

uint method_owner(uint row)
{
    uint count = min(compact_method_count[0u], gParams.hir_capacity);
    if (row >= count)
        return INVALID;
    HirMethodCore core = compact_method_cores[row];
    HirMethodSignature signature = compact_method_signatures[row];
    uint trait_owner = interface_trait_method_owner(core, active_hir_count(),
        compact_hir_core, compact_hir_payload, public_decl_index_by_hir);
    if (trait_owner != INVALID) return trait_owner;
    if (((signature.metadata >> 16u) & 4u) != 0u && !interface_public_inherent_method(signature)) return INVALID;
    uint implementation_rows; uint stride;
    interface_implementation_index_by_hir.GetDimensions(implementation_rows, stride);
    if (core.impl_node < min(active_hir_count(), implementation_rows))
    {
        uint implementation = interface_implementation_index_by_hir[core.impl_node];
        if (implementation != 0u) return 0x80000000u | (implementation - 1u);
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint public_count = min(public_decl_count[0u], gParams.decl_capacity);
    if (row < public_count)
    {
        interface_decl_direct_type_hir[row] = INVALID;
        uint local = public_decl_local_id[row];
        if (local < gParams.decl_capacity)
        {
            uint kind = decl_kind[local];
            if (kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN ||
                kind == HIR_ITEM_KIND_CONST || kind == HIR_ITEM_KIND_TYPE_ALIAS)
            {
                uint hir = decl_hir_node[local];
                if (hir < active_hir_count())
                {
                    uint direct = kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN
                        ? compact_fn_return_type[hir]
                        : kind == HIR_ITEM_KIND_CONST
                            ? compact_const_type[hir]
                            : compact_type_alias_target[hir];
                    if (!((kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN) && direct == INVALID))
                    {
                        interface_decl_direct_type_hir[row] = direct;
                        seed(direct, row);
                    }
                }
            }
        }
    }

    // Method signatures belong to their exported nominal or trait owner.
    // Trait receivers are described by receiver mode, without an impl type.
    if (row < min(compact_method_count[0u], gParams.hir_capacity))
    {
        uint method_owner_id = method_owner(row);
        uint method_node = compact_method_cores[row].node;
        if (method_owner_id != INVALID && method_node < active_hir_count())
        {
            uint receiver = compact_method_signatures[row].impl_receiver_type;
            uint result = compact_fn_return_type[method_node];
            if (receiver != INVALID) seed(receiver, method_owner_id);
            if (result != INVALID) seed(result, method_owner_id);
        }
    }
}
