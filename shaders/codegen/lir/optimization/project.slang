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

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (row == 0u)
        opt_ir_total[0u] = total;
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
