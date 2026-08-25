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
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_block_total;
RWStructuredBuffer<OptIrBlock> opt_ir_blocks;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool is_terminator(uint op)
{
    return semantic_lir_op_has_flag(op, SEMANTIC_LIR_OP_FLAG_TERMINATOR);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
    if (block_id >= block_total) return;

    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    OptIrBlock block = opt_ir_blocks[block_id];
    uint end = block_id + 1u < block_total
        ? opt_ir_blocks[block_id + 1u].position_start : total;
    if (block.position_start >= end || end > total) return;
    uint node = semantic_schedule_order[end - 1u];
    if (node < total && is_terminator(opt_ir_op(opt_ir_core[node])))
        block.terminator = node;
    opt_ir_blocks[block_id] = block;
}
