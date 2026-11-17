// Per token of a round's stream, and one row for the end of the stream:
// whether the token stays. The generated tokens a token owns go before it;
// splice_inserted.slang counts them into the same row.
import gpu_index;
import desugar_common;

StructuredBuffer<uint> sizes;
// Per token: nonzero when the round's feature replaces it.
StructuredBuffer<uint> drop;
RWStructuredBuffer<uint4> splice_marks;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint t = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    uint tokens = sizes[S_SPLICED];
    if (t > tokens || sizes[S_GENERATED] == 0u)
        return;
    bool kept = t < tokens && drop[t] == 0u;
    splice_marks[t] = uint4(kept ? 1u : 0u, 0u, 0u, 0u);
}
