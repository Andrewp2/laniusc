import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_clobber_by_position;
RWStructuredBuffer<uint> x86_location_by_semantic;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.semantic_capacity) return;
    x86_position_by_semantic[row] = X86_LOCATION_INVALID;
    x86_last_use_by_semantic[row] = 0u;
    x86_clobber_by_position[row] = 0u;
    x86_location_by_semantic[row] = X86_LOCATION_INVALID;
}
