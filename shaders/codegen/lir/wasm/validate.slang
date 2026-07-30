import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint target_start; uint page_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<WasmLirInstruction> target_lir_core;
StructuredBuffer<uint> semantic_owner_by_instruction;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint required = target_lir_total[0u];
    if (row == 0u && required > gParams.target_capacity)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_TARGET_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, required);
        InterlockedMin(lowering_status[0u].available_capacity, gParams.target_capacity);
    }
    if (row >= min(required, gParams.target_capacity)) return;
    WasmLirInstruction target = target_lir_core[page_row];
    if ((target.flags & TARGET_LIR_FLAG_UNSUPPORTED) == 0u) return;
    uint hir = target.semantic_instruction < gParams.semantic_capacity
        ? semantic_owner_by_instruction[target.semantic_instruction] : 0xffffffffu;
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
    InterlockedMin(lowering_status[0u].first_unsupported_hir, hir);
}
