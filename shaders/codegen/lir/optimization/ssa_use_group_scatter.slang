// Compacts ordered SSA value boundaries into one group per used value.

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
RWStructuredBuffer<OptIrUseGroup> opt_ir_ssa_use_groups;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.value_capacity;
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
    if (!starts) return;
    uint group_id = opt_ir_ssa_use_group_prefix[order_i];
    if (use_id >= total || group_id >= gParams.value_capacity)
    {
        report_capacity(group_id + 1u);
        return;
    }
    OptIrUseGroup group;
    group.value = opt_ir_ssa_use_values[use_id];
    group.start = order_i;
    group.count = 0u;
    opt_ir_ssa_use_groups[group_id] = group;
}
