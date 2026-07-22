import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<WasmLirInstruction> target_lir_core;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<uint> wasm_object_relocation_flag;
RWStructuredBuffer<uint> wasm_object_symbol_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.target_capacity) return;
    uint total = min(target_lir_total[0u], gParams.target_capacity);
    uint flag = 0u;
    if (row < total)
    {
        WasmLirInstruction target = target_lir_core[row];
        uint semantic_count = semantic_lir_total[0u];
        if (target.semantic_instruction < semantic_count)
        {
            uint op = semantic_lir_core[target.semantic_instruction].op;
            flag = op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_SYMBOL
                ? 1u : 0u;
        }
    }
    wasm_object_relocation_flag[row] = flag;
    wasm_object_symbol_flag[row] = row < total &&
        target_lir_core[row].opcode == WASM_LIR_OP_CALL_SYMBOL ? 1u : 0u;
}
