// The piece writer only visits tokens owned by a machine. Count their
// spans in source order so its two section scans can use compact rows.
import shared.buffers.gpu_index;
import desugar.tokens.desugaring_layout;
import machine_layout;

StructuredBuffer<uint> sizes;
StructuredBuffer<uint> machines;
StructuredBuffer<uint> records;
RWStructuredBuffer<uint4> spans;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint m = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    uint count = sizes[S_F0];
    if (m >= count)
        return;
    uint head = machines[m];
    uint end = records[head * REC_WORDS + REC_END];
    // A later start owns subsequent tokens even in malformed input.
    if (m + 1u < count)
        end = min(end, machines[m + 1u]);
    spans[m] = uint4(end - head, 0u, 0u, 0u);
}
