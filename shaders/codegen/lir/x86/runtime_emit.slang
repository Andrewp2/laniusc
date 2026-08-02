// Runtime bytes are independent artifact rows. Keeping them out of the body
// emitter avoids one serial loop in lane zero and keeps machine instruction
// selection below the shader-size/pipeline-compilation guardrail.

import codegen.lowering_ir;
import codegen.lir.x86.runtime_abi;
import gpu_index;

struct Params
{
    uint target_capacity;
    uint token_capacity;
    uint function_capacity;
    uint artifact_capacity;
    uint target_start;
    uint page_capacity;
    uint reserved0;
    uint reserved1;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<uint> artifact_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

void store_byte(uint pos, uint value)
{
    if (pos >= gParams.artifact_capacity) return;
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
    uint pos = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    if (layout.status != 0u || pos >= layout.runtime_length) return;
    store_byte(layout.runtime_offset + pos, x86_runtime_byte(pos));
}
