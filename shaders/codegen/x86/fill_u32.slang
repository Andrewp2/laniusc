// Fill a flat u32 storage buffer with a short repeated pattern on the GPU.
//
// Backend initialization uses this for large invalid-filled scratch buffers so
// the host does not construct and upload hundreds of MiB of repeated bytes.

import gpu_index;

struct FillParams
{
    uint n_words;
    uint pattern_len;
    uint pattern0;
    uint pattern1;
    uint pattern2;
    uint pattern3;
    uint _pad0;
    uint _pad1;
};

ConstantBuffer<FillParams> gFill;
RWStructuredBuffer<uint> target;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint pattern_value(uint index)
{
    uint slot = gFill.pattern_len == 0u ? 0u : index % gFill.pattern_len;
    if (slot == 0u) return gFill.pattern0;
    if (slot == 1u) return gFill.pattern1;
    if (slot == 2u) return gFill.pattern2;
    return gFill.pattern3;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (word < gFill.n_words)
        target[word] = pattern_value(word);
}
