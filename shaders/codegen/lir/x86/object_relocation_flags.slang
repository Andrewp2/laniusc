import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<uint> x86_object_relocation_flag;
RWStructuredBuffer<uint> x86_object_symbol_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.target_capacity) return;
    uint total = min(target_lir_total[0u], gParams.target_capacity);
    uint op = row < total ? target_lir_core[row].op : 0u;
    x86_object_relocation_flag[row] =
        op == X86_LIR_OP_CALL_SYMBOL || op == X86_LIR_OP_STRING_ADDR ? 1u : 0u;
    x86_object_symbol_flag[row] = op == X86_LIR_OP_CALL_SYMBOL ? 1u : 0u;
}
