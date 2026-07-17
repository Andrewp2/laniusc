// Scatter one compact enum-variant payload row per invocation.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> interface_signature_edge_count;
StructuredBuffer<uint> interface_signature_edge_prefix;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_type_edges;
RWStructuredBuffer<uint> interface_type_edge_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, detail); }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= min(compact_variant_payload_row_count[0u], gParams.hir_capacity))
        return;
    HirVariantPayload payload = compact_variant_payloads[row];
    if (payload.variant >= min(compact_variant_count[0u], gParams.hir_capacity))
    { fail(row); return; }
    uint name_token = compact_variants[payload.variant].name_token;
    uint local = name_token < gParams.token_capacity ? decl_id_by_name_token[name_token] : INVALID;
    uint owner = local < gParams.decl_capacity ? public_decl_index_by_local[local] : INVALID;
    uint target = payload.type_node < gParams.hir_capacity
        ? interface_type_index_by_hir[payload.type_node]
        : INVALID;
    if (owner >= gParams.decl_capacity || payload.ordinal + 1u >= interface_signature_edge_count[owner] ||
        target >= gParams.hir_capacity)
    { fail(row); return; }
    uint destination = interface_type_edge_total[0u] +
                       interface_signature_edge_prefix[owner] + payload.ordinal;
    interface_type_edges[destination] = target;
    interface_type_edge_written[destination] = 1u;
}
