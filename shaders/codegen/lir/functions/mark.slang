import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint function_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_owner_by_instruction;
StructuredBuffer<uint> semantic_function_id_by_hir;
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
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (row >= total) return;
    uint semantic_row = semantic_schedule_order[row];
    uint id = semantic_function_id_by_hir[semantic_owner_by_instruction[semantic_row]];
    uint previous_id = row == 0u ? INVALID
        : semantic_function_id_by_hir[
            semantic_owner_by_instruction[semantic_schedule_order[row - 1u]]];
    function_start_flag[row] = id != INVALID && (row == 0u || previous_id != id) ? 1u : 0u;
}
