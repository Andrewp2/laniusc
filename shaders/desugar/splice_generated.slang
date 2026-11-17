// Per generated token: its row at its owner's place in the new stream,
// before the owner itself.
import gpu_index;
import desugar_common;

StructuredBuffer<uint> sizes;
StructuredBuffer<TokenRow> generated;
StructuredBuffer<uint> generated_file;
StructuredBuffer<uint> generated_owner;
StructuredBuffer<uint4> splice_marks;
StructuredBuffer<uint4> splice_scan;
RWStructuredBuffer<TokenRow> spliced;
RWStructuredBuffer<uint> spliced_file;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint g = linear_dispatch_thread_id_2d(tid, DESUGAR_DISPATCH_X_STRIDE);
    if (g >= sizes[S_GENERATED] || sizes[S_OUT] == 0u)
        return;
    uint owner = generated_owner[g];
    uint4 row = splice_marks[owner];
    uint4 through = splice_scan[owner];
    uint base = through.x + through.y - row.x - row.y;
    uint at = base + (g - row.z);
    spliced[at] = generated[g];
    spliced_file[at] = generated_file[g];
}
