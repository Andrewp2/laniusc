// Size synthetic declaration-signature records and their edge ranges. One
// thread handles one persisted public declaration; scans provide stable bases.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> hir_variant_payload_count;
RWStructuredBuffer<uint> interface_signature_type_flag;
RWStructuredBuffer<uint> interface_signature_edge_count;
RWStructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail)
{
    atomic_u32_or(interface_status, 0u, 4096u);
    atomic_u32_min(interface_status, 1u, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint persisted = linear_thread_id(dtid);
    if (persisted >= gParams.decl_capacity)
        return;
    interface_signature_type_flag[persisted] = 0u;
    interface_signature_edge_count[persisted] = 0u;
    interface_signature_type_by_decl[persisted] = INVALID;
    if (persisted >= min(public_decl_count[0u], gParams.decl_capacity))
        return;
    uint local = public_decl_local_id[persisted];
    if (local >= gParams.decl_capacity)
    {
        fail(persisted);
        return;
    }
    uint kind = decl_kind[local];
    if (kind == HIR_ITEM_KIND_FN || kind == HIR_ITEM_KIND_EXTERN_FN)
    {
        uint hir = decl_hir_node[local];
        uint token = hir < gParams.hir_capacity ? hir_token_pos[hir] : INVALID;
        if (token >= gParams.token_capacity)
        {
            fail(persisted);
            return;
        }
        interface_signature_type_flag[persisted] = 1u;
        interface_signature_edge_count[persisted] = call_param_count[token] + 1u;
    }
    else if (kind == HIR_ITEM_KIND_STRUCT || kind == HIR_ITEM_KIND_ENUM)
        interface_signature_type_flag[persisted] = 1u;
    else if (kind == HIR_ITEM_KIND_ENUM_VARIANT)
    {
        uint hir = decl_hir_node[local];
        if (hir >= gParams.hir_capacity) { fail(persisted); return; }
        interface_signature_type_flag[persisted] = 1u;
        interface_signature_edge_count[persisted] = hir_variant_payload_count[hir] + 1u;
    }
    else if (kind != HIR_ITEM_KIND_CONST && kind != HIR_ITEM_KIND_TYPE_ALIAS)
        fail(persisted);
}
