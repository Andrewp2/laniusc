// Checks that every ordered use belongs to exactly one finalized value group.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint parameter_capacity;
    uint block_argument_capacity;
    uint value_capacity;
    uint call_argument_capacity;
    uint aggregate_element_capacity;
    uint block_capacity;
    uint access_capacity;
    uint incoming_capacity;
    uint hir_capacity;
    uint use_capacity;
    uint reserved1;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_use_total;
StructuredBuffer<uint> opt_ir_ssa_use_values;
StructuredBuffer<uint> opt_ir_ssa_use_order;
StructuredBuffer<uint> opt_ir_ssa_use_group_prefix;
StructuredBuffer<uint> opt_ir_ssa_use_group_total;
StructuredBuffer<OptIrUseGroup> opt_ir_ssa_use_groups;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_failure(uint use_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_GROUP_VALIDATE,
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
    uint total = min(opt_ir_ssa_use_total[0u], gParams.use_capacity);
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    bool starts = order_i == 0u;
    if (!starts && use_id < total)
    {
        uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
        starts = previous_id >= total ||
            opt_ir_ssa_use_values[previous_id] !=
                opt_ir_ssa_use_values[use_id];
    }
    uint prefix = opt_ir_ssa_use_group_prefix[order_i];
    uint group_id = starts ? prefix : prefix - 1u;
    uint group_total = min(opt_ir_ssa_use_group_total[0u],
        gParams.value_capacity);
    bool valid = use_id < total && prefix >= (starts ? 0u : 1u) &&
        group_id < group_total;
    if (valid)
    {
        OptIrUseGroup group = opt_ir_ssa_use_groups[group_id];
        valid = group.value == opt_ir_ssa_use_values[use_id] &&
            group.start <= order_i && order_i - group.start < group.count;
    }
    if (!valid) report_failure(use_id);
}
