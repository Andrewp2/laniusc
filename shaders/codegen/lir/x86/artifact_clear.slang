import gpu_index;

struct Params { uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> artifact_bytes;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint word = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (word < (gParams.artifact_capacity + 3u) / 4u) artifact_bytes[word] = 0u;
}
