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
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
RWStructuredBuffer<uint> opt_ir_edge_count_by_block;
RWStructuredBuffer<uint> opt_ir_edge_scan_dispatch_args;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.block_capacity, opt_ir_block_total[0u]);
    if (block_id == 0u)
    {
        uint groups = (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE;
        opt_ir_edge_scan_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
        opt_ir_edge_scan_dispatch_args[1u] =
            max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
        opt_ir_edge_scan_dispatch_args[2u] = 1u;
    }
    if (block_id >= total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    bool has_fallthrough = block_id + 1u < total &&
        opt_ir_blocks[block_id + 1u].function_id == block.function_id;
    uint edge_count = has_fallthrough ? 1u : 0u;
    if (block.terminator != INVALID && block.terminator < gParams.semantic_capacity)
    {
        uint role = semantic_lir_control_role(opt_ir_op(opt_ir_core[block.terminator]));
        if (role == SEMANTIC_LIR_CONTROL_CONDITIONAL_BRANCH)
            edge_count = (has_fallthrough ? 1u : 0u) + 1u;
        else if (role == SEMANTIC_LIR_CONTROL_ELSE_BRANCH ||
                 role == SEMANTIC_LIR_CONTROL_BRANCH)
            edge_count = 1u;
        else if (role == SEMANTIC_LIR_CONTROL_RETURN)
            edge_count = 0u;
    }
    opt_ir_edge_count_by_block[block_id] = edge_count;
}
