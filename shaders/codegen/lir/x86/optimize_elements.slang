// One lane per aggregate element row counts, for its aggregate, the element
// rows that fit the dense array layout (lir/x86/aggregate_facts.slang). With
// every row counted, count, allocation_words and scatter index a wide
// literal's elements directly instead of scanning them on one lane.

import codegen.lowering_ir;
import codegen.lir.x86.liveness_dependencies;
import codegen.lir.x86.aggregate_facts;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<X86LivenessDependencies> x86_liveness_dependencies;
RWStructuredBuffer<uint> x86_aggregate_facts;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint element_total = min(gParams.aggregate_capacity,
        semantic_lir_aggregate_element_total[0u]);
    if (row >= element_total) return;
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    SemanticLirAggregateElement element = semantic_lir_aggregate_elements[row];
    uint aggregate = element.aggregate_instruction;
    if (aggregate >= total) return;
    // The element range dependency discovery published for the aggregate.
    X86LivenessDependencies deps = x86_liveness_dependencies[aggregate];
    if (deps.variable_kind != VARIABLE_AGGREGATE_ELEMENTS ||
        row < deps.variable_start || row - deps.variable_start >= deps.variable_count)
        return;
    uint start = deps.variable_start;
    if (x86_dense_element(element, aggregate, row, start,
            semantic_lir_aggregate_elements[start].word_count))
    {
        uint ignored;
        InterlockedAdd(x86_aggregate_facts[aggregate], 1u, ignored);
    }
}
