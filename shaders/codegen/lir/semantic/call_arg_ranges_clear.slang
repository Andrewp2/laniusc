import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> semantic_lir_call_arg_start_scratch;
RWStructuredBuffer<uint> semantic_lir_call_arg_count_scratch;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.semantic_capacity) return;
    semantic_lir_call_arg_start_scratch[row] = INVALID;
    semantic_lir_call_arg_count_scratch[row] = 0u;
}
