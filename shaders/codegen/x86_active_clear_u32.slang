// Clear a u32 scratch buffer over a GPU-resident active range.
//
// The active dispatch-argument buffer stores the indirect dispatch triplet in
// words 0..2 and the active item count in word 3. This lets capacity-sized
// scratch buffers be initialized over the same compact range used by the next
// GPU pass, without a CPU readback.

import gpu_index;

StructuredBuffer<uint> active_dispatch_args;
RWStructuredBuffer<uint> target;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint ACTIVE_COUNT_WORD = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint active_count = active_dispatch_args[ACTIVE_COUNT_WORD];
    if (row < active_count)
        target[row] = 0u;
}
