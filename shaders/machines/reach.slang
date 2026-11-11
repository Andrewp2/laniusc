// Per state: one doubling step of the states a machine can reach from it.
// A row holds one bit per state of the machine. A step joins each row with
// the rows of the states it names, so after n steps a row holds every state
// at most 2^n transitions away. Eight steps cover a machine of 256 states.
import gpu_index;
import machine_common;

struct ReachParams
{
    uint state_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<ReachParams> gReach;
StructuredBuffer<uint> records;
StructuredBuffer<uint4> scan_a;
StructuredBuffer<uint> machines;
StructuredBuffer<uint> states;
// Two rows of four words per state.
StructuredBuffer<uint4> rows_in;
RWStructuredBuffer<uint4> rows_out;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint word_of(uint4 low, uint4 high, uint index)
{
    uint4 half = index < 4u ? low : high;
    uint part = index & 3u;
    if (part == 0u)
        return half.x;
    if (part == 1u)
        return half.y;
    if (part == 2u)
        return half.z;
    return half.w;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (i >= gReach.state_count)
        return;
    uint head = machines[scan_a[states[i]].x - 1u];
    uint first = scan_a[head].y;
    uint count = min(scan_a[records[head * REC_WORDS + REC_END] - 1u].y - first, MAX_STATES);
    uint4 low = rows_in[i * 2u];
    uint4 high = rows_in[i * 2u + 1u];
    uint4 out_low = low;
    uint4 out_high = high;
    for (uint j = 0u; j < count; j += 1u)
    {
        if (((word_of(low, high, j >> 5u) >> (j & 31u)) & 1u) != 0u)
        {
            out_low |= rows_in[(first + j) * 2u];
            out_high |= rows_in[(first + j) * 2u + 1u];
        }
    }
    rows_out[i * 2u] = out_low;
    rows_out[i * 2u + 1u] = out_high;
}
