// Per generated token: its row at the place of its machine's item in the
// new stream.
import gpu_index;
import desugar_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenOut> generated;
StructuredBuffer<uint> generated_file;
StructuredBuffer<uint> generated_machine;
StructuredBuffer<uint4> machine_tokens;
StructuredBuffer<uint4> splice_scan;
RWStructuredBuffer<TokenOut> spliced;
RWStructuredBuffer<uint> spliced_file;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint g = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (g >= sizes[S_GENERATED] || sizes[S_OUT] == 0u)
        return;
    uint4 machine = machine_tokens[generated_machine[g]];
    uint item = machine.z;
    uint base = item == 0u ? 0u : splice_scan[item - 1u].x;
    uint at = base + (g - machine.x);
    spliced[at] = generated[g];
    spliced_file[at] = generated_file[g];
}
