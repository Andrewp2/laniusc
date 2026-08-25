// Compacts declaration group starts from the stable access ordering.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint parameter_capacity;
    uint local_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<uint> opt_ir_access_group_start_flag;
StructuredBuffer<uint> opt_ir_access_group_prefix;
RWStructuredBuffer<OptIrAccessGroup> opt_ir_access_groups;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.declaration_capacity;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_access_total[0u], gParams.access_capacity);
    if (order_i >= total || opt_ir_access_group_start_flag[order_i] == 0u)
        return;

    uint access_id = opt_ir_access_order[order_i];
    uint group_id = opt_ir_access_group_prefix[order_i];
    if (access_id >= total || group_id >= gParams.declaration_capacity)
    {
        report_capacity(group_id + 1u);
        return;
    }

    OptIrAccessGroup group;
    group.subject = opt_ir_accesses[access_id].subject;
    group.start = order_i;
    group.count = 0u;
    group.flags = 0u;
    opt_ir_access_groups[group_id] = group;
}
