import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> semantic_struct_hir_by_name_token;
RWStructuredBuffer<uint> semantic_struct_field_count_by_hir;
RWStructuredBuffer<uint> semantic_function_id_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row < gParams.n_tokens)
    {
        semantic_struct_hir_by_name_token[row] = INVALID;
        semantic_function_id_by_token[row] = INVALID;
    }
    if (row < gParams.n_hir_nodes)
        semantic_struct_field_count_by_hir[row] = 0u;
}
