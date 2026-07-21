import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<uint> scheduled_function_id;
StructuredBuffer<uint> function_start_flag;
StructuredBuffer<uint> function_prefix;
RWStructuredBuffer<uint> function_start;
RWStructuredBuffer<uint> compact_function_id;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= total || function_start_flag[row] == 0u) return;
    uint compact = function_prefix[row];
    if (compact >= gParams.function_capacity) return;
    function_start[compact] = row;
    compact_function_id[compact] = scheduled_function_id[row];
}
