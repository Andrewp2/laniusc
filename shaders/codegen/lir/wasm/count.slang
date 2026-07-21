import codegen.lir.wasm.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
RWStructuredBuffer<uint> target_lir_count;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.semantic_capacity) return;
    uint count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    uint semantic_row = row < count ? semantic_schedule_order[row] : 0u;
    target_lir_count[row] = row < count
        ? wasm_lir_count(semantic_lir_core[semantic_row],
                         semantic_lir_operands[semantic_row])
        : 0u;
}
