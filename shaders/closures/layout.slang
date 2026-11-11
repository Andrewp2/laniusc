// Compacts the captures into one list in token order and gives each closure
// its range of that list. `capture_scan.x` counts captures through a token.
import gpu_index;
import closure_common;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint4> depth_scan;
StructuredBuffer<uint4> capture_marks;
StructuredBuffer<uint4> capture_scan;
RWStructuredBuffer<uint> records;
RWStructuredBuffer<uint4> captures;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (i >= token_count[0])
        return;

    uint4 mark = capture_marks[i];
    if (mark.x == 1u)
        captures[capture_scan[i].x - 1u] = uint4(mark.w, i, mark.y, mark.z);

    uint through = depth_scan[i].y;
    uint before = i > 0u ? depth_scan[i - 1u].y : 0u;
    if (through == before)
        return;
    uint row = (through - 1u) * REC_WORDS;
    uint body_first = records[row + REC_BODY_FIRST];
    uint body_last = records[row + REC_BODY_LAST];
    if (body_last < body_first)
        return;
    uint first = body_first > 0u ? capture_scan[body_first - 1u].x : 0u;
    records[row + REC_CAP_FIRST] = first;
    records[row + REC_CAP_COUNT] = capture_scan[body_last].x - first;
}
