import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
StructuredBuffer<uint> x86_artifact_bytes;
RWStructuredBuffer<uint> x86_object_text_bytes;
RWStructuredBuffer<uint> x86_object_rodata_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint load_byte(uint pos)
{
    return (x86_artifact_bytes[pos >> 2u] >> ((pos & 3u) * 8u)) & 0xffu;
}

void store_byte(RWStructuredBuffer<uint> output, uint pos, uint value)
{
    uint word_i = pos >> 2u;
    uint shift = (pos & 3u) * 8u;
    uint mask = 0xffu << shift;
    uint old_value = output[word_i];
    for (;;)
    {
        uint next = (old_value & ~mask) | ((value & 0xffu) << shift);
        uint prior;
        InterlockedCompareExchange(output[word_i], old_value, next, prior);
        if (prior == old_value) return;
        old_value = prior;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.artifact_capacity) return;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    uint wrapper_length = layout.body_offset - layout.text_offset;
    uint text_length = wrapper_length + layout.body_length + layout.runtime_length;
    if (row < text_length)
        store_byte(x86_object_text_bytes, row, load_byte(layout.text_offset + row));
    if (row < layout.rodata_length)
        store_byte(x86_object_rodata_bytes, row, load_byte(layout.rodata_offset + row));
}
