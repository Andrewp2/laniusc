import codegen.lir.lowering_ir;
import shared.buffers.gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
StructuredBuffer<uint> x86_artifact_bytes;
RWStructuredBuffer<uint> x86_object_text_bytes;
RWStructuredBuffer<uint> x86_object_rodata_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

// Pack up to four live bytes. Object sections start at arbitrary byte
// offsets and the last destination word can be partial.
uint load_word(uint start, uint bytes)
{
    uint word = start >> 2u;
    uint shift = (start & 3u) * 8u;
    uint value = x86_artifact_bytes[word] >> shift;
    if (bytes * 8u > 32u - shift)
        value |= x86_artifact_bytes[word + 1u] << (32u - shift);
    return value & (0xffffffffu >> ((4u - bytes) * 8u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint word = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint row = word * 4u;
    if (row >= gParams.artifact_capacity) return;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    uint wrapper_length = layout.body_offset - layout.text_offset;
    uint text_length = wrapper_length + layout.body_length + layout.runtime_length;
    if (row < text_length)
        x86_object_text_bytes[word] = load_word(layout.text_offset + row, min(4u, text_length - row));
    if (row < layout.rodata_length)
        x86_object_rodata_bytes[word] = load_word(layout.rodata_offset + row, min(4u, layout.rodata_length - row));
}
