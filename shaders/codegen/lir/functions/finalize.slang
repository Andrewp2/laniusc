import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<uint> function_count;
StructuredBuffer<uint> function_start;
StructuredBuffer<uint> compact_function_id;
RWStructuredBuffer<TargetLirFunction> target_function;
RWStructuredBuffer<uint> function_index_by_semantic;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.function_capacity, function_count[0u]);
    if (row >= count) return;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    uint start = min(function_start[row], total);
    uint end = row + 1u < count ? min(function_start[row + 1u], total) : total;
    TargetLirFunction out_value;
    out_value.function_id = compact_function_id[row];
    out_value.instruction_start = start;
    out_value.instruction_count = end - start;
    out_value.flags = 0u;
    target_function[row] = out_value;
    if (out_value.function_id < gParams.function_capacity)
        function_index_by_semantic[out_value.function_id] = row;
}
