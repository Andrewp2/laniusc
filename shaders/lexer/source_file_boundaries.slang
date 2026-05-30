import gpu_index;

StructuredBuffer<uint> source_file_count;
StructuredBuffer<uint> source_file_start;
StructuredBuffer<uint> source_file_len;
RWStructuredBuffer<uint> source_file_start_flags;
RWStructuredBuffer<uint> source_file_end_flags;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void source_file_boundaries(uint3 tid: SV_DispatchThreadID)
{
    uint file_i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (file_i >= source_file_count[0])
        return;

    uint start = source_file_start[file_i];
    uint end = start + source_file_len[file_i];
    source_file_start_flags[start] = 1u;
    source_file_end_flags[end] = 1u;
}
