import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_function_id_by_hir;
RWStructuredBuffer<uint> opt_ir_position_by_node;
RWStructuredBuffer<uint> opt_ir_block_start_flag;
RWStructuredBuffer<uint> opt_ir_block_scan_dispatch_args;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint function_for_node(uint node)
{
    uint source = opt_ir_source_hir[node];
    return source < gParams.hir_capacity
        ? semantic_function_id_by_hir[source] : INVALID;
}

bool starts_labeled_block(uint op)
{
    uint role = semantic_lir_control_role(op);
    return role == SEMANTIC_LIR_CONTROL_BLOCK_LABEL ||
        role == SEMANTIC_LIR_CONTROL_LOOP_HEADER ||
        role == SEMANTIC_LIR_CONTROL_MERGE_LABEL;
}

bool ends_block(uint op)
{
    return semantic_lir_op_has_flag(op, SEMANTIC_LIR_OP_FLAG_TERMINATOR);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position == 0u)
    {
        uint groups = (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE;
        opt_ir_block_scan_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
        opt_ir_block_scan_dispatch_args[1u] =
            max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
        opt_ir_block_scan_dispatch_args[2u] = 1u;
    }
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    if (node >= total) return;
    opt_ir_position_by_node[node] = position;

    uint op = opt_ir_op(opt_ir_core[node]);
    uint function_id = function_for_node(node);
    bool starts = position == 0u || starts_labeled_block(op);
    if (position != 0u)
    {
        uint previous = semantic_schedule_order[position - 1u];
        if (previous >= total)
            starts = true;
        else
            starts = starts || function_for_node(previous) != function_id ||
                ends_block(opt_ir_op(opt_ir_core[previous]));
    }
    opt_ir_block_start_flag[position] = starts ? 1u : 0u;
}
