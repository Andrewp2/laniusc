import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_owner_by_instruction;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_to_target_start;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<uint> wasm_object_relocation_flag;
StructuredBuffer<uint> wasm_object_relocation_prefix;
StructuredBuffer<uint> wasm_object_symbol_prefix;
StructuredBuffer<WasmLirFunction> wasm_lir_functions;
StructuredBuffer<uint> wasm_code_entry_offset;
RWStructuredBuffer<WasmObjectRelocationRow> wasm_object_relocations;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint RELOCATION_LOCAL_FUNCTION = 1u;
static const uint RELOCATION_SYMBOL = 2u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint semantic_count = semantic_lir_total[0u];
    if (row >= semantic_count || wasm_object_relocation_flag[row] == 0u) return;

    uint semantic_row = semantic_schedule_order[row];
    uint target_row = semantic_to_target_start[semantic_row];
    uint target_total = min(target_lir_total[0u], gParams.target_capacity);
    if (target_row >= target_total) return;
    SemanticLirCore instruction = semantic_lir_core[semantic_row];
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    uint function_id =
        semantic_function_id_by_hir[semantic_owner_by_instruction[semantic_row]];
    if (function_id >= gParams.function_capacity) return;
    WasmLirFunction function = wasm_lir_functions[function_id];
    uint relative_instruction_byte = target_byte_offset[target_row] - function.body_byte_start;

    WasmObjectRelocationRow relocation;
    // Padded code-entry size (5), padded local-group count (5), semantic local
    // declarations, and the two six-byte target-private temporaries precede
    // the instruction stream. The final +1 addresses the first LEB byte after
    // the call opcode.
    relocation.body_byte_offset = wasm_code_entry_offset[function_id] + 22u +
        function.local_count * 6u + relative_instruction_byte + 1u;
    bool symbolic = instruction.op == SEMANTIC_LIR_OP_CALL_SYMBOL;
    relocation.target_kind = symbolic ? RELOCATION_SYMBOL : RELOCATION_LOCAL_FUNCTION;
    relocation.target_index = symbolic ? wasm_object_symbol_prefix[row] : operands.a;
    relocation.addend = 0u;
    relocation.library_id = symbolic ? operands.a : 0u;
    relocation.unit_id = symbolic ? operands.b : 0u;
    relocation.local_index = symbolic ? operands.c : 0u;
    relocation.reserved = 0u;
    wasm_object_relocations[wasm_object_relocation_prefix[row]] = relocation;
}
