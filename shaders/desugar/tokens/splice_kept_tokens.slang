// Per token the round keeps: its row at its place in the new stream, after
// the generated tokens it owns. `splice_scan` is the inclusive prefix sum of
// the splice rows: kept tokens in x, generated ones in y.
import shared.buffers.gpu_index;
import desugaring_layout;

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenRow> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint4> splice_marks;
StructuredBuffer<uint4> splice_scan;
RWStructuredBuffer<TokenRow> spliced;
RWStructuredBuffer<uint> spliced_file;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (t >= sizes[S_SPLICED] || sizes[S_OUT] == 0u)
        return;
    if (splice_marks[t].x == 0u)
        return;
    uint4 through = splice_scan[t];
    uint at = through.x + through.y - 1u;
    spliced[at] = tokens_out[t];
    spliced_file[at] = token_file_id[t];
}
