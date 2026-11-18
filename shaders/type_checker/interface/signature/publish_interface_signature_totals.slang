// Publish complete graph sizes and shared primitive leaves. Constant generic
// headers name their declared scalar even when no signature uses the parameter.

import type_checker.interface.scalar_leaves;
import primitive_types;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_signature_type_total;
StructuredBuffer<uint> interface_signature_edge_total;
StructuredBuffer<uint> interface_predicate_total;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_complete_type_count;
RWStructuredBuffer<uint> interface_complete_edge_total;
static const uint TYPE_WORDS = 9u;
static const uint TYPE_KIND_SCALAR = 1u;
[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint hir_count = min(interface_type_count[0u], gParams.hir_capacity);
    for (uint scalar = SCALAR_UNIT; scalar <= SCALAR_NEVER; scalar++)
    {
        uint base = interface_scalar_leaf_index(hir_count, scalar) * TYPE_WORDS;
        interface_types[base] = TYPE_KIND_SCALAR;
        interface_types[base + 1u] = scalar;
        for (uint word = 2u; word < TYPE_WORDS; word++)
            interface_types[base + word] = 0u;
    }
    interface_complete_type_count[0u] =
        hir_count + INTERFACE_SCALAR_LEAF_COUNT + interface_signature_type_total[0u] + interface_predicate_total[0u];
    interface_complete_edge_total[0u] =
        interface_type_edge_total[0u] + interface_signature_edge_total[0u];
}
