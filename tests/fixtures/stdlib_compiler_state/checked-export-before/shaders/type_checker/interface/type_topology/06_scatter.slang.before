// Scatter reachable types and publish HIR-to-persisted type indices.

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> interface_type_reverse_flag;
StructuredBuffer<uint> interface_type_reverse_prefix;
RWStructuredBuffer<uint> interface_type_hir_order;
RWStructuredBuffer<uint> interface_type_index_by_hir;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint reverse_row = linear_thread_id(dtid);
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (reverse_row >= active || interface_type_reverse_flag[reverse_row] == 0u)
        return;
    uint node = active - 1u - reverse_row;
    uint dst = interface_type_reverse_prefix[reverse_row];
    if (dst >= gParams.hir_capacity)
        return;
    interface_type_hir_order[dst] = node;
    interface_type_index_by_hir[node] = dst;
}
