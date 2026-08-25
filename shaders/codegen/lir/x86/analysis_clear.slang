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
RWStructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_next_rax_clobber_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_live_by_semantic;
RWStructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
RWStructuredBuffer<uint> x86_location_by_semantic;
RWStructuredBuffer<uint> x86_function_start;
RWStructuredBuffer<uint> x86_function_end;
RWStructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
RWStructuredBuffer<uint> x86_stack_slot_count_by_function;
RWStructuredBuffer<uint> x86_frame_slot_count_by_function;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;
RWStructuredBuffer<uint> x86_decl_location_by_token;
RWStructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
RWStructuredBuffer<uint> x86_direct_call_count_by_function;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row < gParams.semantic_capacity)
    {
        x86_position_by_semantic[row] = INVALID;
        x86_next_rax_clobber_by_semantic[row] = INVALID;
        x86_last_use_by_semantic[row] = 0u;
        x86_live_by_semantic[row] = 0u;
        X86ValueAnalysis value_analysis;
        value_analysis.value = 0u;
        value_analysis.known = 0u;
        value_analysis.replacement = row;
        x86_value_by_semantic[row] = value_analysis;
        x86_location_by_semantic[row] = INVALID;
    }
    if (row < gParams.token_capacity)
    {
        x86_decl_location_by_token[row] = INVALID;
        X86DeclarationAnalysis analysis;
        analysis.last_read = 0u;
        analysis.last_access = 0u;
        analysis.definition = INVALID;
        analysis.read_count = 0u;
        x86_decl_analysis_by_token[row] = analysis;
    }
    if (row < gParams.function_capacity)
    {
        x86_function_start[row] = INVALID;
        x86_function_end[row] = 0u;
        X86FunctionRegisterAnalysis register_analysis;
        // Parallel indexing lowers this sentinel with InterlockedMin. The
        // constant-time allocation finalizer converts it back to the public
        // zero-means-no-call representation.
        register_analysis.first_call = INVALID;
        register_analysis.first_rdx_clobber = 0u;
        register_analysis.first_rcx_clobber = 0u;
        register_analysis.flags = 0u;
        x86_register_analysis_by_function[row] = register_analysis;
        x86_stack_slot_count_by_function[row] = 0u;
        x86_frame_slot_count_by_function[row] = 0u;
        x86_saved_gpr_mask_by_function[row] = 0u;
        x86_direct_call_count_by_function[row] = 0u;
    }
}
