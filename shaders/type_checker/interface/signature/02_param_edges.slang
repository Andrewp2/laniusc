// Scatter compact function parameter types into synthesized function signatures.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> public_decl_index_by_hir;
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
uint linear_thread_id(uint3 d) { return d.x + d.y * MAX_GROUPS_X * WG_SIZE; }
void fail(uint d) { atomic_u32_or(interface_status, 0u, 4096u); atomic_u32_min(interface_status, 1u, d); }
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= min(compact_param_count[0u], gParams.hir_capacity)) return;
    HirParam param = compact_params[row];
    uint owner = param.owner < gParams.hir_capacity ? public_decl_index_by_hir[param.owner] : INVALID;
    if (owner >= gParams.decl_capacity) return;
    uint edge_count = interface_signature_edge_count[owner];
    uint target = param.type_node < gParams.hir_capacity
        ? interface_type_index_by_hir[param.type_node] : INVALID;
    if (param.ordinal + 1u >= edge_count || target >= gParams.hir_capacity)
    { fail(row); return; }
    uint destination = interface_type_edge_total[0u] +
        interface_signature_edge_prefix[owner] + param.ordinal;
    interface_type_edges[destination] = target;
    interface_type_edge_written[destination] = 1u;
}
