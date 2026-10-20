import codegen.lir.wasm.common;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

// Points each fixed-array argument passed as a slice at its call argument.
// frame_words revalidates the hint against the argument, so a stale entry
// from an earlier compilation is harmless.
struct Params { uint semantic_capacity; uint n_tokens; uint function_capacity; uint call_arg_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> semantic_lir_call_arg_total;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
RWStructuredBuffer<uint> wasm_frame_view_hint;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= min(gParams.call_arg_capacity, semantic_lir_call_arg_total[0u])) return;
    SemanticLirCallArg argument = semantic_lir_call_args[row];
    uint count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (argument.value_instruction >= count) return;
    if (wasm_argument_view_length(argument, opt_ir_core[argument.value_instruction],
                                  opt_ir_core, count) !=
        WASM_LIR_INVALID)
        wasm_frame_view_hint[argument.value_instruction] = row;
}
