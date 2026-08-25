// Materializes deterministic function-relative spill locations from the
// parallel width scan. Each invocation owns one scheduled OptIR node.

import codegen.lowering_ir;
import codegen.optimization_ir;
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
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> x86_function_start;
StructuredBuffer<uint> x86_stack_words_by_position;
StructuredBuffer<uint> x86_stack_prefix_by_position;
RWStructuredBuffer<uint> x86_location_by_semantic;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position >= total) return;
    uint row = semantic_schedule_order[position];
    if (row >= total || x86_stack_words_by_position[position] == 0u ||
        x86_location_by_semantic[row] != INVALID) return;
    uint owner = opt_ir_source_hir[row];
    if (owner >= gParams.function_capacity) return;
    uint function_id = semantic_function_id_by_hir[owner];
    if (function_id >= gParams.function_capacity) return;
    uint start = x86_function_start[function_id];
    if (start > position || start >= total) return;
    uint base = x86_stack_prefix_by_position[start];
    uint prefix = x86_stack_prefix_by_position[position];
    x86_location_by_semantic[row] = prefix >= base ? prefix - base : INVALID;
}
