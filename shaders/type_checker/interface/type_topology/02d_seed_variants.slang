// Seed public enum-variant payload roots from compact family rows.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> public_decl_index_by_local;
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
    if (row >= min(compact_variant_payload_row_count[0u], gParams.hir_capacity)) return;
    HirVariantPayload payload = compact_variant_payloads[row];
    uint variant_count = min(compact_variant_count[0u], gParams.hir_capacity);
    if (payload.variant >= variant_count) return;
    uint name_token = compact_variants[payload.variant].name_token;
    uint local = name_token < gParams.token_capacity ? decl_id_by_name_token[name_token] : INVALID;
    uint owner = local < gParams.decl_capacity ? public_decl_index_by_local[local] : INVALID;
    if (owner >= gParams.decl_capacity) return;
    if (!type_node(payload.type_node) || interface_type_parent[payload.type_node] != INVALID)
    { atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, row); return; }
    uint prior = atomic_u32_compare_exchange(interface_type_seed_owner, payload.type_node, INVALID, owner);
    if (prior != INVALID && prior != owner)
    { atomic_u32_or(interface_status, 0u, 256u); atomic_u32_min(interface_status, 1u, row); }
}
