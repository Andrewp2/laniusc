// Reads the elements of every aggregate optimize_close made live, one lane
// per element row. The lane extends the element value's last use to the
// aggregate and claims the value; a claimed value with dependencies is walked
// from here exactly as optimize_close would have walked it. Aggregates first
// reached by such a walk read their elements on the walking lane, so every
// element of every live aggregate is read once more after this pass, whatever
// the order. Last uses are maxima and live marks are claims, so the result
// matches the single walk.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.execution_owner;
import codegen.lir.x86.liveness_dependencies;
import codegen.lir.x86.liveness_walk;
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
    // Only aggregates optimize_close expanded: those it claimed. Their
    // element rows are the ones its walk would have read.
    if (aggregate >= total || x86_live_by_semantic[aggregate] == 0u) return;
    X86LivenessDependencies deps = x86_liveness_dependencies[aggregate];
    if (deps.variable_kind != VARIABLE_AGGREGATE_ELEMENTS ||
        row < deps.variable_start || row - deps.variable_start >= deps.variable_count)
        return;
    uint value = element.value_instruction;
    if (x86_liveness_read(aggregate, deps.position, deps.function_id, value,
            total, gParams.function_capacity))
        x86_liveness_walk_from(value, total, gParams.function_capacity, false);
}
