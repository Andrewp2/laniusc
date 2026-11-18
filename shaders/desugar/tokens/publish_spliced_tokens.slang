// Per token of the new stream: its row and file into the lexer's buffers,
// where the next round and the parser read them.
import shared.buffers.gpu_index;
import desugaring_layout;

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenRow> spliced;
StructuredBuffer<uint> spliced_file;
RWStructuredBuffer<TokenRow> tokens_out;
RWStructuredBuffer<uint> token_file_id;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (i >= sizes[S_OUT])
        return;
    tokens_out[i] = spliced[i];
    token_file_id[i] = spliced_file[i];
}
