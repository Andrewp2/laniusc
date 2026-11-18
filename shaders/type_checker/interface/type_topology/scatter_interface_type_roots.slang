// Publish one root index per exported annotation. Each checked subtree occupies
// its own contiguous reverse-preorder interval.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> interface_type_reverse_flag;
StructuredBuffer<uint> interface_type_reverse_prefix;
RWStructuredBuffer<uint> interface_type_index_by_hir;
RWStructuredBuffer<uint> interface_status;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (row >= active || interface_type_reverse_flag[row] == 0u) return;
    uint node = active - 1u - row;
    uint start = interface_type_reverse_prefix[row];
    uint count = interface_type_reverse_flag[row];
    if (start >= gParams.hir_capacity || count > gParams.hir_capacity - start)
    {
        atomic_u32_or(interface_status, 0u, 32768u);
        atomic_u32_min(interface_status, 1u, node);
        return;
    }
    uint index = start + count - 1u;
    interface_type_index_by_hir[node] = index;
}
