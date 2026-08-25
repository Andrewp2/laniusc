// Marks the first ordered use of every dense SSA value.

import codegen.lowering_ir;
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
RWStructuredBuffer<uint> opt_ir_ssa_use_group_start_flag;
RWStructuredBuffer<uint> opt_ir_ssa_use_group_scan_dispatch_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void report_failure(uint use_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_GROUP,
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
    if (order_i == 0u)
    {
        uint groups = max(1u,
            (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE);
        opt_ir_ssa_use_group_scan_dispatch_args[0u] =
            min(groups, MAX_GROUPS_X);
        opt_ir_ssa_use_group_scan_dispatch_args[1u] = max(1u,
            (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
        opt_ir_ssa_use_group_scan_dispatch_args[2u] = 1u;
    }
    if (order_i >= total) return;
    uint use_id = opt_ir_ssa_use_order[order_i];
    if (use_id >= total)
    {
        opt_ir_ssa_use_group_start_flag[order_i] = 0u;
        report_failure(use_id);
        return;
    }
    bool starts = order_i == 0u;
    if (!starts)
    {
        uint previous_id = opt_ir_ssa_use_order[order_i - 1u];
        starts = previous_id >= total ||
            opt_ir_ssa_use_values[previous_id] !=
                opt_ir_ssa_use_values[use_id];
    }
    opt_ir_ssa_use_group_start_flag[order_i] = starts ? 1u : 0u;
}
