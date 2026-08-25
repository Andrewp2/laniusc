import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint function_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> target_lir_offset;
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
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= total || function_start_flag[row] == 0u) return;
    uint compact = function_prefix[row];
    if (compact >= gParams.function_capacity) return;
    uint semantic_row = semantic_schedule_order[row];
    function_start[compact] = target_lir_offset[row];
    compact_function_id[compact] =
        semantic_function_id_by_hir[opt_ir_source_hir[semantic_row]];
}
