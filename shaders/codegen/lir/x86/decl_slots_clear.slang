import codegen.lowering_ir;
import gpu_index;

struct Params { uint token_capacity; uint parameter_capacity; uint local_capacity; uint function_capacity; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> x86_decl_location_by_token;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row < gParams.token_capacity)
        x86_decl_location_by_token[row] = X86_LOCATION_INVALID;
    if (row < gParams.function_capacity)
        x86_saved_gpr_mask_by_function[row] = 0u;
}
