import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<uint> scheduled_function_id;
RWStructuredBuffer<uint> function_start_flag;
RWStructuredBuffer<uint> function_index_by_semantic;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row < gParams.function_capacity)
        function_index_by_semantic[row] = INVALID;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= total) return;
    uint id = scheduled_function_id[row];
    function_start_flag[row] = id != INVALID && (row == 0u || scheduled_function_id[row - 1u] != id)
        ? 1u : 0u;
}
