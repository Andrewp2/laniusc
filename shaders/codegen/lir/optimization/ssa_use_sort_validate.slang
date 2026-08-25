// Independently proves value ordering, stable tie order, and uniqueness.

import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint item_capacity;
    uint key_bits;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_use_total;
StructuredBuffer<uint> opt_ir_ssa_use_values;
StructuredBuffer<uint> opt_ir_ssa_use_order;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_failure(uint use_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_ORDER,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, use_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_ssa_use_total[0u], gParams.item_capacity);
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    if (use_id >= total)
    {
        report_failure(use_id);
        return;
    }
    if (order_i == 0u) return;
    uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
    bool valid = previous_id < total;
    if (valid)
    {
        uint previous_value = opt_ir_ssa_use_values[previous_id];
        uint value = opt_ir_ssa_use_values[use_id];
        valid = previous_value < value ||
            (previous_value == value && previous_id < use_id);
    }
    if (!valid) report_failure(use_id);
}
