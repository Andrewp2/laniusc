import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint call_arg_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_lir_call_arg_total;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= min(gParams.call_arg_capacity, semantic_lir_call_arg_total[0u])) return;
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    SemanticLirCallArg argument = semantic_lir_call_args[row];
    if (argument.call_instruction >= total || argument.value_instruction >= total) return;
    uint position = x86_position_by_semantic[argument.call_instruction];
    if (position >= total) return;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[argument.value_instruction], position, ignored);
}
