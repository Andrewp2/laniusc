import gpu_index;

struct Params { uint n_hir_nodes; uint n_tokens; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> semantic_value_used;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_dispatch_thread_id_2d(dtid, 16776960u);
    // Clear the allocated domain on every job, including smaller jobs reusing
    // a previously larger resident workspace.
    if (token < gParams.n_tokens) semantic_value_used[token] = 0u;
}
