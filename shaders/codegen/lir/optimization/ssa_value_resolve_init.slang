// Initializes the temporary value-link graph. Canonical producers terminate
// at their dense value; declaration reads are filled from the reaching-
// definition relation by the following pass.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint parameter_capacity;
    uint block_argument_capacity;
    uint value_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeResults> opt_ir_results;
RWStructuredBuffer<uint> opt_ir_ssa_value_link_out;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 101u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    if (row >= total) return;

    uint op = opt_ir_op(opt_ir_core[row]);
    bool produces = semantic_lir_produces_value(op);
    uint link = 0u;
    if (produces && op != SEMANTIC_LIR_OP_VALUE_GET)
    {
        uint value = opt_ir_results[row].value_out;
        if (value < gParams.value_capacity)
            link = opt_ir_pack_ssa_value_link(
                OPT_IR_SSA_VALUE_LINK_VALUE, value);
        else
            report_structure_failure(row);
    }
    else if (!produces && opt_ir_results[row].value_out != INVALID)
        report_structure_failure(row);

    opt_ir_ssa_value_link_out[row] = link;
}
