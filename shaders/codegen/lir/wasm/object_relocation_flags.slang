import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_op_by_instruction;
RWStructuredBuffer<uint> wasm_object_relocation_flag;
RWStructuredBuffer<uint> wasm_object_symbol_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = semantic_lir_total[0u];
    if (row >= total) return;
    uint op = semantic_op_by_instruction[semantic_schedule_order[row]];
    wasm_object_relocation_flag[row] =
        op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        op == SEMANTIC_LIR_OP_CONST_STRING ? 1u : 0u;
    wasm_object_symbol_flag[row] = op == SEMANTIC_LIR_OP_CALL_SYMBOL ? 1u : 0u;
}
