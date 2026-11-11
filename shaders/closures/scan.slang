// One doubling step of an inclusive prefix sum over four-word rows. The host
// records one step per power of two below the row count.
import gpu_index;

struct ScanParams
{
    uint count;
    uint step;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<ScanParams> gScan;
StructuredBuffer<uint4> scan_in;
RWStructuredBuffer<uint4> scan_out;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (i >= gScan.count)
        return;
    uint4 value = scan_in[i];
    if (i >= gScan.step)
        value += scan_in[i - gScan.step];
    scan_out[i] = value;
}
