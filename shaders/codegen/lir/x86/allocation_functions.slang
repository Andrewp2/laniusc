// Reduces the global spill prefix to constant-size per-function metadata.
// Function invocations do not inspect function bodies.

import codegen.lowering_ir;
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
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<uint> x86_function_start;
StructuredBuffer<uint> x86_function_end;
StructuredBuffer<uint> x86_stack_words_by_position;
StructuredBuffer<uint> x86_stack_prefix_by_position;
RWStructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
RWStructuredBuffer<uint> x86_stack_slot_count_by_function;
RWStructuredBuffer<uint> x86_frame_slot_count_by_function;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid,
        DISPATCH_X_STRIDE);
    uint function_total = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    if (function_id >= function_total) return;

    uint start = x86_function_start[function_id];
    uint end = min(x86_function_end[function_id],
        gParams.semantic_capacity);
    uint words = 0u;
    if (start < end)
    {
        uint last = end - 1u;
        uint base = x86_stack_prefix_by_position[start];
        uint limit = x86_stack_prefix_by_position[last] +
            x86_stack_words_by_position[last];
        words = limit >= base ? limit - base : 0u;
    }
    x86_stack_slot_count_by_function[function_id] = words;
    x86_frame_slot_count_by_function[function_id] = words;

    X86FunctionRegisterAnalysis analysis =
        x86_register_analysis_by_function[function_id];
    if (analysis.first_call == INVALID)
    {
        analysis.first_call = 0u;
        analysis.flags = 0u;
    }
    else
    {
        // Conservatively retain declaration homes across calls. A later
        // parallel interval allocator can refine this without changing the
        // spill-layout contract.
        analysis.flags = X86_FUNCTION_REGISTER_CALL_WITH_LOOP;
    }
    analysis.first_rdx_clobber = 0u;
    analysis.first_rcx_clobber = 0u;
    x86_register_analysis_by_function[function_id] = analysis;
}
