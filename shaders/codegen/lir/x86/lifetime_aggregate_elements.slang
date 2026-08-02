import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint call_arg_capacity; uint aggregate_capacity; uint reserved0; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint element_total = min(gParams.aggregate_capacity,
        semantic_lir_aggregate_element_total[0u]);
    if (row >= element_total) return;
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    SemanticLirAggregateElement element = semantic_lir_aggregate_elements[row];
    if (element.aggregate_instruction >= total || element.value_instruction >= total) return;
    uint position = x86_position_by_semantic[element.aggregate_instruction];
    if (position >= total) return;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[element.value_instruction], position, ignored);
}
