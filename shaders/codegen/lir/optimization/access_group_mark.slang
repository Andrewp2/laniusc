// Marks the first row of each declaration in the stable access ordering.
// Memory accesses occupy the following radix domain and are intentionally
// excluded: they become effect chains rather than SSA declaration values.

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
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_access_order;
RWStructuredBuffer<uint> opt_ir_declaration_access_total;
RWStructuredBuffer<uint> opt_ir_access_group_start_flag;
RWStructuredBuffer<uint> opt_ir_local_definition_by_access;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_access_total[0u], gParams.access_capacity);
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= total)
    {
        opt_ir_access_group_start_flag[order_i] = 0u;
        return;
    }

    opt_ir_local_definition_by_access[access_id] = INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    if (opt_ir_access_domain(kind) != 0u)
    {
        opt_ir_access_group_start_flag[order_i] = 0u;
        InterlockedMin(opt_ir_declaration_access_total[0u], order_i);
        return;
    }

    bool starts_group = order_i == 0u;
    if (!starts_group)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        starts_group = previous_id >= total ||
            opt_ir_access_domain(opt_ir_access_kinds[previous_id]) != 0u ||
            opt_ir_accesses[previous_id].subject !=
                opt_ir_accesses[access_id].subject;
    }
    opt_ir_access_group_start_flag[order_i] = starts_group ? 1u : 0u;
}
