import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint required = semantic_lir_total[0u];
    if (row == 0u && required > gParams.semantic_capacity)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_SEMANTIC_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, required);
        InterlockedMin(lowering_status[0u].available_capacity, gParams.semantic_capacity);
    }
    if (row >= min(required, gParams.semantic_capacity)) return;
    SemanticLirCore core = semantic_lir_core[row];
    if (core.op == SEMANTIC_LIR_OP_INVALID ||
        (core.flags & SEMANTIC_LIR_FLAG_UNSUPPORTED) != 0u)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
}
