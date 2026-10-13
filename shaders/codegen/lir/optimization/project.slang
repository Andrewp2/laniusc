import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_owner_by_instruction;
RWStructuredBuffer<uint> opt_ir_total;
RWStructuredBuffer<OptIrNodeControl> opt_ir_control;
RWStructuredBuffer<OptIrNodeResults> opt_ir_results;
RWStructuredBuffer<uint> opt_ir_semantic_row;
RWStructuredBuffer<uint> opt_ir_source_hir;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (row == 0u)
    {
        // Bounded workspaces may process a prefix for diagnostics, but that
        // prefix is never a successful compilation of the complete program.
        uint required = semantic_lir_total[0u];
        if (required > gParams.semantic_capacity)
        {
            InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_SEMANTIC_CAPACITY);
            InterlockedMax(lowering_status[0u].required_capacity, required);
            InterlockedMin(lowering_status[0u].available_capacity, gParams.semantic_capacity);
        }
        opt_ir_total[0u] = total;
    }
    if (row >= total) return;

    OptIrNodeControl control;
    control.block_id = INVALID;
    control.region_id = INVALID;
    opt_ir_control[row] = control;

    OptIrNodeResults results;
    results.value_out = INVALID;
    results.effect_out = INVALID;
    opt_ir_results[row] = results;

    opt_ir_semantic_row[row] = row;
    opt_ir_source_hir[row] = semantic_owner_by_instruction[row];
}
