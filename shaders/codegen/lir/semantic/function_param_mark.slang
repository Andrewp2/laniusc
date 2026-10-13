import hir_records;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> semantic_function_flag;
RWStructuredBuffer<uint> semantic_param_flag;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (row >= gParams.param_capacity) return;
    uint count = min(compact_param_count[0u], gParams.param_capacity);
    uint owner = row < count ? compact_params[row].owner : 0xffffffffu;
    semantic_param_flag[row] = owner < gParams.n_hir_nodes &&
        semantic_function_flag[owner] != 0u ? 1u : 0u;
}
