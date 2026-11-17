// Per source token kept by the splice: its row at its place in the new
// stream.
import gpu_index;
import desugar_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint4> splice_marks;
StructuredBuffer<uint4> splice_scan;
RWStructuredBuffer<TokenOut> spliced;
RWStructuredBuffer<uint> spliced_file;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (t >= sizes[S_SPLICED] || sizes[S_OUT] == 0u)
        return;
    if (splice_marks[t].y != 1u)
        return;
    uint at = splice_scan[t].x - 1u;
    spliced[at] = tokens_out[t];
    spliced_file[at] = token_file_id[t];
}
