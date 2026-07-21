import gpu_index;

struct Params { uint token_capacity; uint parameter_capacity; uint local_capacity; uint function_capacity; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> x86_frame_slot_by_decl_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (token < gParams.token_capacity)
        x86_frame_slot_by_decl_token[token] = INVALID;
}
