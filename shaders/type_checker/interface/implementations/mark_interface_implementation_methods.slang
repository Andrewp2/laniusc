// Mark the real lexical implementation owner before assigning export rows.
import hir_records;
import atomics;
import type_checker.interface.method_parameters;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
RWStructuredBuffer<uint> interface_implementation_flag;
RWStructuredBuffer<uint> interface_implementation_first_method_row;
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (row >= min(compact_method_count[0u], active)) return;
    uint rows; uint stride;
    interface_implementation_flag.GetDimensions(rows, stride);
    HirMethodCore method = compact_method_cores[row];
    if (method.impl_node >= min(active, rows) || method.owner != method.impl_node) return;
    atomic_u32_min(interface_implementation_first_method_row, method.impl_node, row);
    if (interface_public_inherent_method(compact_method_signatures[row]))
        atomic_u32_or(interface_implementation_flag, method.impl_node, 1u);
}
