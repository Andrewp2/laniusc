// Finalizes compact declaration group ranges and produces one indirect
// workgroup per group for block-local definition resolution.

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
StructuredBuffer<uint> opt_ir_declaration_access_total;
StructuredBuffer<uint> opt_ir_access_group_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_access_order;
RWStructuredBuffer<OptIrAccessGroup> opt_ir_access_groups;
RWStructuredBuffer<uint> opt_ir_access_group_dispatch_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint MAX_GROUPS_X = 65535u;

void report_structure_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint group_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint group_total = min(opt_ir_access_group_total[0u],
        gParams.declaration_capacity);
    uint access_total = min(opt_ir_access_total[0u], gParams.access_capacity);
    uint declaration_total = min(opt_ir_declaration_access_total[0u],
        access_total);

    if (group_id == 0u)
    {
        uint dispatched = max(group_total, 1u);
        opt_ir_access_group_dispatch_args[0u] = min(dispatched, MAX_GROUPS_X);
        opt_ir_access_group_dispatch_args[1u] =
            (dispatched + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
        opt_ir_access_group_dispatch_args[2u] = 1u;
    }
    if (group_id >= group_total) return;

    OptIrAccessGroup group = opt_ir_access_groups[group_id];
    uint end = group_id + 1u < group_total
        ? opt_ir_access_groups[group_id + 1u].start
        : declaration_total;
    bool valid = group.start < end && end <= declaration_total;
    if (valid)
    {
        uint first_id = opt_ir_access_order[group.start];
        uint last_id = opt_ir_access_order[end - 1u];
        valid = first_id < access_total && last_id < access_total &&
            opt_ir_access_domain(opt_ir_access_kinds[first_id]) == 0u &&
            opt_ir_access_domain(opt_ir_access_kinds[last_id]) == 0u &&
            opt_ir_accesses[first_id].subject == group.subject &&
            opt_ir_accesses[last_id].subject == group.subject;
        if (group_id > 0u)
            valid = valid && opt_ir_access_groups[group_id - 1u].subject <
                group.subject;
    }
    if (!valid)
    {
        report_structure_failure(group.start);
        return;
    }

    group.count = end - group.start;
    opt_ir_access_groups[group_id] = group;
}
