import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<uint> target_lir_flags;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint required = target_lir_total[0u];
    if (row == 0u && required > gParams.target_capacity)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_TARGET_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, required);
        InterlockedMin(lowering_status[0u].available_capacity, gParams.target_capacity);
    }
    if (row >= min(required, gParams.target_capacity)) return;
    if ((target_lir_flags[row] & TARGET_LIR_FLAG_UNSUPPORTED) == 0u) return;
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
    InterlockedMin(lowering_status[0u].first_unsupported_hir, target_lir_core[row].source_hir);
}
