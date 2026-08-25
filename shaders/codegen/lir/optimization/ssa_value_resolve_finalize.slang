// Publishes resolved declaration-read aliases in the canonical node results.

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
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> opt_ir_ssa_value_link_in;
RWStructuredBuffer<OptIrNodeResults> opt_ir_results;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 103u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    if (row >= total) return;

    uint op = opt_ir_op(opt_ir_core[row]);
    uint link = opt_ir_ssa_value_link_in[row];
    uint kind = opt_ir_ssa_value_link_kind(link);
    uint value = opt_ir_ssa_value_link_payload(link);
    uint value_total = min(opt_ir_ssa_value_total[0u],
        gParams.value_capacity);
    bool produces = semantic_lir_produces_value(op);
    bool valid = produces
        ? kind == OPT_IR_SSA_VALUE_LINK_VALUE && value < value_total
        : kind == OPT_IR_SSA_VALUE_LINK_INVALID;

    if (valid && op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        OptIrNodeResults result = opt_ir_results[row];
        result.value_out = value;
        opt_ir_results[row] = result;
    }
    else if (valid && produces)
        valid = opt_ir_results[row].value_out == value;

    if (!valid) report_structure_failure(row);
}
