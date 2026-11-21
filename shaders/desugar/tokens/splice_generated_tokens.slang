// A generated token's ordinal plus the kept source tokens before its
// owner gives its position in the merged stream.
import shared.buffers.gpu_index;
import desugaring_layout;

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenRow> generated;
StructuredBuffer<uint> generated_file;
StructuredBuffer<uint> generated_owner;
StructuredBuffer<uint> insert_kept_prefix;
RWStructuredBuffer<TokenRow> spliced;
RWStructuredBuffer<uint> spliced_file;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint g = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (g >= sizes[S_GENERATED] || sizes[S_OUT] == 0u)
        return;
    uint at = g + insert_kept_prefix[generated_owner[g]];
    spliced[at] = generated[g];
    spliced_file[at] = generated_file[g];
}
