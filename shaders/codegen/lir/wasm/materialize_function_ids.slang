import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint semantic_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<WasmLirInstruction> target_lir_core;
StructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;
RWStructuredBuffer<uint> scheduled_function_id;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= total) return;
    uint semantic_row = target_lir_core[row].semantic_instruction;
    scheduled_function_id[row] = semantic_row < gParams.semantic_capacity
        ? semantic_lir_schedule[semantic_row].function_id : INVALID;
}
