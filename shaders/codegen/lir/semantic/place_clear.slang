import gpu_index;
struct Params { uint n_hir_nodes; uint n_tokens; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint4> semantic_place_storage_by_token;
RWStructuredBuffer<uint> semantic_place_address_by_token;
RWStructuredBuffer<uint> semantic_place_function_flags;
RWStructuredBuffer<uint> semantic_receiver_call_by_hir;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint declaration_capacity; uint stride;
    semantic_place_storage_by_token.GetDimensions(declaration_capacity, stride);
    if (row < declaration_capacity)
    {
        semantic_place_storage_by_token[row] = uint4(0u, 0u, 0u, 0u);
        semantic_place_address_by_token[row] = 0xffffffffu;
    }
    if (row < gParams.n_hir_nodes)
    {
        semantic_place_function_flags[row] = 0u;
        semantic_receiver_call_by_hir[row] = 0u;
    }
}
