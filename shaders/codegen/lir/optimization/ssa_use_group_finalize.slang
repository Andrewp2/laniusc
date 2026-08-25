// Finalizes exact ranges for the compact SSA value-use groups.

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
StructuredBuffer<uint> opt_ir_ssa_use_group_total;
StructuredBuffer<uint> opt_ir_ssa_use_values;
StructuredBuffer<uint> opt_ir_ssa_use_order;
RWStructuredBuffer<OptIrUseGroup> opt_ir_ssa_use_groups;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_GROUP,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint group_id = linear_dispatch_thread_id_2d(dtid,
        DISPATCH_X_STRIDE);
    uint group_total = min(opt_ir_ssa_use_group_total[0u],
        gParams.value_capacity);
    if (group_id >= group_total) return;
    uint use_total = min(opt_ir_ssa_use_total[0u],
        gParams.use_capacity);
    OptIrUseGroup group = opt_ir_ssa_use_groups[group_id];
    uint end = group_id + 1u < group_total
        ? opt_ir_ssa_use_groups[group_id + 1u].start : use_total;
    bool valid = group.start < end && end <= use_total;
    if (valid)
    {
        uint first_id = opt_ir_ssa_use_order[group.start];
        uint last_id = opt_ir_ssa_use_order[end - 1u];
        valid = first_id < use_total && last_id < use_total &&
            opt_ir_ssa_use_values[first_id] == group.value &&
            opt_ir_ssa_use_values[last_id] == group.value;
        if (group_id > 0u)
            valid = valid &&
                opt_ir_ssa_use_groups[group_id - 1u].value < group.value;
    }
    if (!valid)
    {
        report_failure(group.start);
        return;
    }
    group.count = end - group.start;
    opt_ir_ssa_use_groups[group_id] = group;
}
