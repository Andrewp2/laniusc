// Scatter one compact enum-variant payload row per invocation.

import hir_records;
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> decl_count_out;
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
void fail(uint detail) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, detail); atomic_u32_min(interface_status, 2u, 5u); }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= min(compact_variant_payload_row_count[0u], gParams.hir_capacity))
        return;
    HirVariantPayload payload = compact_variant_payloads[row];
    uint variant_count = min(compact_variant_count[0u], gParams.hir_capacity);
    if (payload.variant >= variant_count)
    {
        fail(row);
        atomic_u32_min(interface_status, 3u, 51u);
        return;
    }
    uint decl_count = min(decl_count_out[0u], gParams.decl_capacity);
    uint local = decl_count >= variant_count
        ? decl_count - variant_count + payload.variant : INVALID;
    uint owner = local < gParams.decl_capacity ? public_decl_index_by_local[local] : INVALID;
    uint target = payload.type_node < gParams.hir_capacity
        ? interface_type_index_by_hir[payload.type_node]
        : INVALID;
    if (owner >= gParams.decl_capacity)
        return;
    if (payload.ordinal + 1u >= interface_signature_edge_count[owner])
    { fail(row); atomic_u32_min(interface_status, 3u, 53u); return; }
    if (target >= gParams.hir_capacity)
    { fail(row); atomic_u32_min(interface_status, 3u, 54u); return; }
    uint destination = interface_type_edge_total[0u] +
                       interface_signature_edge_prefix[owner] + payload.ordinal;
    interface_type_edges[destination] = target;
    interface_type_edge_written[destination] = 1u;
}
