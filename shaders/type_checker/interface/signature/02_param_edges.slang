// Scatter function parameter types into their synthesized function signature.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> interface_signature_edge_count;
StructuredBuffer<uint> interface_signature_edge_prefix;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_type_edges;
RWStructuredBuffer<uint> interface_type_edge_written;
RWStructuredBuffer<uint> interface_status;
static const uint HIR_PARAM = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint detail) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, detail); }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= min(hir_status[5u], gParams.hir_capacity) || hir_kind[node] != HIR_PARAM)
        return;
    uint4 param = hir_param_record[node];
    uint owner = param.x < gParams.hir_capacity ? public_decl_index_by_hir[param.x] : 0xffffffffu;
    uint ordinal = param.y;
    if (owner >= gParams.decl_capacity)
        return;
    uint edge_count = interface_signature_edge_count[owner];
    uint type_node = hir_param_type_node[node];
    uint target = type_node < gParams.hir_capacity ? interface_type_index_by_hir[type_node] : 0xffffffffu;
    if (ordinal + 1u >= edge_count || target >= gParams.hir_capacity)
    {
        fail(node);
        return;
    }
    interface_type_edges[interface_type_edge_total[0u] +
                         interface_signature_edge_prefix[owner] + ordinal] = target;
    interface_type_edge_written[interface_type_edge_total[0u] +
                                interface_signature_edge_prefix[owner] + ordinal] = 1u;
}
