import codegen.lir.wasm.byte_common;
import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint target_capacity;
    uint target_start;
    uint page_capacity;
    uint reserved0;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<WasmLirInstruction> target_lir_core;
RWStructuredBuffer<uint> target_byte_length;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint position = gParams.target_start + page_row;
    if (position >= gParams.target_capacity) return;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    target_byte_length[position] = position < total
        ? wasm_lir_byte_len(target_lir_core[page_row])
        : 0u;
}
