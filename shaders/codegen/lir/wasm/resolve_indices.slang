import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint target_capacity;
    uint n_tokens;
    uint semantic_capacity;
    uint target_start;
    uint page_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<uint> wasm_local_index_by_decl_token;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<WasmLirFunction> wasm_lir_functions;
StructuredBuffer<WasmLirOperands> target_lir_operands;
RWStructuredBuffer<WasmLirInstruction> target_lir_core;

static const uint INVALID = 0xffffffffu;
static const uint WASM_SYNTHETIC_I32_TEMP = 0xfffffffeu;
static const uint WASM_SYNTHETIC_F32_TEMP = 0xfffffffdu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint count = min(target_lir_total[0u], gParams.target_capacity);
    if (row >= count) return;
    WasmLirInstruction inst = target_lir_core[page_row];
    if (inst.opcode == WASM_LIR_OP_LOCAL_GET || inst.opcode == WASM_LIR_OP_LOCAL_SET)
    {
        uint declaration = inst.immediate;
        uint function_id = inst.semantic_instruction < gParams.semantic_capacity
            ? semantic_function_id_by_hir[
                opt_ir_source_hir[inst.semantic_instruction]] : INVALID;
        if ((declaration == WASM_SYNTHETIC_I32_TEMP ||
             declaration == WASM_SYNTHETIC_F32_TEMP) && function_id != INVALID)
        {
            WasmLirFunction function = wasm_lir_functions[function_id];
            inst.immediate = function.param_value_count + function.local_value_count +
                (declaration == WASM_SYNTHETIC_F32_TEMP ? 1u : 0u);
        }
        else
            inst.immediate = declaration != INVALID && declaration < gParams.n_tokens
                ? wasm_local_index_by_decl_token[declaration] : INVALID;
        if (inst.immediate != INVALID &&
            target_lir_operands[page_row].metadata == 7u)
            inst.immediate += target_lir_operands[page_row].c;
        if (inst.immediate == INVALID)
            inst.flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    }
    target_lir_core[page_row] = inst;
}
