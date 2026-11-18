// Zeroes the first `words` words of `target`.
import shared.buffers.gpu_index;

struct ClearParams
{
    uint words;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ClearParams> gClear;
RWStructuredBuffer<uint> target;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (i < gClear.words)
        target[i] = 0u;
}
