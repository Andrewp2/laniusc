import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_method_count;
RWStructuredBuffer<uint> method_lookup_head;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint method = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    if (method >= count)
        return;
    method_lookup_head[method * 2u] = 0u;
    method_lookup_head[method * 2u + 1u] = 0u;
}
