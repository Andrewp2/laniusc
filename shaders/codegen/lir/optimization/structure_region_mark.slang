// Marks real structured-control openers in scheduled OptIR order.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> semantic_schedule_order;
RWStructuredBuffer<uint> opt_ir_region_start_flag;
RWStructuredBuffer<uint> opt_ir_region_scan_dispatch_args;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

bool opens_region(uint op)
{
    return op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    if (position == 0u)
    {
        uint groups = (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE;
        opt_ir_region_scan_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
        opt_ir_region_scan_dispatch_args[1u] =
            max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
        opt_ir_region_scan_dispatch_args[2u] = 1u;
    }
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    bool opener = node < total && opens_region(opt_ir_op(opt_ir_core[node]));
    opt_ir_region_start_flag[position] = opener ? 1u : 0u;
}
