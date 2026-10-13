// Counts and prefixes use the same source-root row domain as type allocation.
// A serialized tree has one edge for every node except its root.
struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> interface_type_reverse_flag;
RWStructuredBuffer<uint> interface_type_edge_count;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (row >= min(compact_hir_count[0u], gParams.hir_capacity)) return;
    uint count = interface_type_reverse_flag[row];
    interface_type_edge_count[row] = count == 0u ? 0u : count - 1u;
}
