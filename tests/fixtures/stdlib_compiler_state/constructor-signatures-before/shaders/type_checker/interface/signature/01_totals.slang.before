// Publish complete graph sizes and the shared implicit-void leaf.

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_type_edge_total;
StructuredBuffer<uint> interface_signature_type_total;
StructuredBuffer<uint> interface_signature_edge_total;
RWStructuredBuffer<uint> interface_types;
RWStructuredBuffer<uint> interface_complete_type_count;
RWStructuredBuffer<uint> interface_complete_edge_total;
static const uint TYPE_WORDS = 9u;
static const uint TYPE_KIND_SCALAR = 1u;
static const uint TY_VOID = 1u;
[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint hir_count = min(interface_type_count[0u], gParams.hir_capacity);
    uint base = hir_count * TYPE_WORDS;
    interface_types[base + 0u] = TYPE_KIND_SCALAR;
    interface_types[base + 1u] = TY_VOID;
    interface_types[base + 2u] = 0u;
    interface_types[base + 3u] = 0u;
    interface_types[base + 4u] = 0u;
    interface_types[base + 5u] = 0u;
    interface_types[base + 6u] = 0u;
    interface_types[base + 7u] = 0u;
    interface_types[base + 8u] = 0u;
    interface_complete_type_count[0u] =
        hir_count + 1u + min(interface_signature_type_total[0u], gParams.decl_capacity);
    interface_complete_edge_total[0u] =
        interface_type_edge_total[0u] + interface_signature_edge_total[0u];
}
