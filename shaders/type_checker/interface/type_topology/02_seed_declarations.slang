// Seed direct dense type roots owned by public declarations and associated
// methods.  Method signatures are exported as members rather than ordinary
// declarations, but their return types still belong to the owning public type
// declaration's reachable interface graph.

import hir_records;
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
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
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> public_decl_index_by_local;
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
static const uint METHOD_VIS_PUBLIC = 1u;
static const uint METHOD_SIGNATURE_INHERENT_IMPL = 4u;
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
    if (((signature.metadata >> 16u) & METHOD_SIGNATURE_INHERENT_IMPL) == 0u ||
        (signature.metadata & 0xffffu) != METHOD_VIS_PUBLIC)
        return INVALID;
    uint receiver = signature.impl_receiver_type;
    if (receiver >= active_hir_count())
        return INVALID;
    uint receiver_token = compact_hir_core[receiver].token_start;
    if (receiver_token >= gParams.token_capacity)
        return INVALID;
    if (type_expr_ref_tag[receiver_token] != TYPE_REF_INSTANCE)
        return INVALID;
    uint instance = type_expr_ref_payload[receiver_token];
    if (instance >= gParams.token_capacity)
        return INVALID;
    uint declaration_token = type_instance_decl_token[instance];
    if (declaration_token >= gParams.token_capacity)
        return INVALID;
    uint local = decl_id_by_name_token[declaration_token];
    return local < gParams.decl_capacity ? public_decl_index_by_local[local] : INVALID;
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

    // Public inherent methods are represented as associated members.  Seed
    // their return type under the owning public declaration so the later
    // topology and member normalization passes assign it a persisted index.
    if (row < min(compact_method_count[0u], gParams.hir_capacity))
    {
        uint method_owner_id = method_owner(row);
        uint method_node = compact_method_cores[row].node;
        if (method_owner_id != INVALID && method_node < active_hir_count())
            seed(compact_fn_return_type[method_node], method_owner_id);
    }
}
