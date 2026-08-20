import codegen.lowering_ir;
import gpu_index;

struct Params { uint token_capacity; uint parameter_capacity; uint local_capacity; uint function_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_function_count;
RWStructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> x86_frame_slot_count_by_function;
StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
StructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.function_capacity, target_function_count[0u]);
    if (row >= count) return;
    TargetLirFunction function = target_functions[row];
    uint function_id = function.function_id;
    uint frame_slots = function_id < gParams.function_capacity
        ? x86_frame_slot_count_by_function[function_id] : 0u;
    bool stackless = function_id < gParams.function_capacity &&
        frame_slots == 0u &&
        x86_saved_gpr_mask_by_function[function_id] == 0u;
    bool leaf = stackless &&
        x86_register_analysis_by_function[function_id].first_call == 0u;
    function.flags = frame_slots | (leaf ? X86_TARGET_FUNCTION_FRAMELESS :
        stackless ? X86_TARGET_FUNCTION_STACKLESS_CALLER : 0u);
    target_functions[row] = function;
}
