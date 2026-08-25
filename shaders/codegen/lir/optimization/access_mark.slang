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
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> semantic_schedule_order;
RWStructuredBuffer<uint> opt_ir_access_flag;
RWStructuredBuffer<uint> opt_ir_access_scan_dispatch_args;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position == 0u)
    {
        uint groups = (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE;
        opt_ir_access_scan_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
        opt_ir_access_scan_dispatch_args[1u] =
            max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
        opt_ir_access_scan_dispatch_args[2u] = 1u;
    }
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    opt_ir_access_flag[position] = node < total &&
        opt_ir_access_kind(opt_ir_core[node]) != OPT_IR_ACCESS_INVALID ? 1u : 0u;
}
