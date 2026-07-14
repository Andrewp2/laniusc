// Scatter one enum-variant payload type per invocation. The parser currently
// exposes four payload columns; flattening (variant, ordinal) keeps this pass
// parallel even while that parser ABI is being generalized.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> hir_variant_payload_count;
StructuredBuffer<uint> hir_variant_payload_node;
StructuredBuffer<uint> interface_signature_edge_count;
StructuredBuffer<uint> interface_signature_edge_prefix;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_type_edges;
RWStructuredBuffer<uint> interface_type_edge_written;
RWStructuredBuffer<uint> interface_status;
static const uint PAYLOAD_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, detail); }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint variant = row / PAYLOAD_STRIDE;
    uint ordinal = row - variant * PAYLOAD_STRIDE;
    if (variant >= min(hir_status[5u], gParams.hir_capacity) ||
        ordinal >= hir_variant_payload_count[variant])
        return;
    uint owner = public_decl_index_by_hir[variant];
    uint type_node = hir_variant_payload_node[variant * PAYLOAD_STRIDE + ordinal];
    uint target = type_node < gParams.hir_capacity ? interface_type_index_by_hir[type_node] : 0xffffffffu;
    if (owner >= gParams.decl_capacity || ordinal + 1u >= interface_signature_edge_count[owner] ||
        target >= gParams.hir_capacity)
    { fail(row); return; }
    uint destination = interface_type_edge_total[0u] +
                       interface_signature_edge_prefix[owner] + ordinal;
    interface_type_edges[destination] = target;
    interface_type_edge_written[destination] = 1u;
}
