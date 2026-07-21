import codegen.lir.wasm.byte_common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint artifact_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<WasmLirInstruction> target_lir_core;
StructuredBuffer<uint> target_byte_length;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<uint> artifact_length;
RWStructuredBuffer<uint> artifact_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

void store_byte(uint pos, uint value)
{
    if (pos >= min(gParams.artifact_capacity, artifact_length[0u])) return;
    uint word_i = pos >> 2u;
    uint shift = (pos & 3u) * 8u;
    uint mask = 0xffu << shift;
    uint old_value = artifact_bytes[word_i];
    for (;;)
    {
        uint next = (old_value & ~mask) | ((value & 0xffu) << shift);
        uint prior;
        InterlockedCompareExchange(artifact_bytes[word_i], old_value, next, prior);
        if (prior == old_value) return;
        old_value = prior;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (position >= total) return;
    WasmLirInstruction inst = target_lir_core[position];
    uint len = target_byte_length[position];
    uint offset = target_byte_offset[position];
    for (uint byte_i = 0u; byte_i < len; byte_i += 1u)
        store_byte(offset + byte_i, wasm_lir_byte(inst, byte_i));
}
