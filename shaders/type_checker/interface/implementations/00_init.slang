// Implementation inventory is indexed by actual lexical HIR owners.
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> interface_implementation_flag;
RWStructuredBuffer<uint> interface_implementation_index_by_hir;
RWStructuredBuffer<uint> interface_implementation_member_count;
RWStructuredBuffer<uint> interface_implementation_method_count;
RWStructuredBuffer<uint> interface_implementation_first_method_row;
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint count; uint stride;
    interface_implementation_index_by_hir.GetDimensions(count, stride);
    if (row >= min(gParams.hir_capacity, count)) return;
    interface_implementation_flag[row] = 0u;
    interface_implementation_index_by_hir[row] = 0u;
    interface_implementation_member_count[row] = 0u;
    interface_implementation_method_count[row] = 0u;
    interface_implementation_first_method_row[row] = 0xffffffffu;
}
