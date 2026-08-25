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
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> opt_ir_block_start_flag;
StructuredBuffer<uint> opt_ir_block_prefix;
StructuredBuffer<uint> opt_ir_block_total;
RWStructuredBuffer<OptIrNodeControl> opt_ir_control;
RWStructuredBuffer<OptIrBlock> opt_ir_blocks;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint block_total = opt_ir_block_total[0u];
    if (position == 0u && block_total > gParams.block_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, block_total);
        lowering_status[0u].available_capacity = gParams.block_capacity;
    }
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    if (node >= total) return;
    uint start = opt_ir_block_start_flag[position];
    uint inclusive = opt_ir_block_prefix[position] + start;
    if (inclusive == 0u) return;
    uint block_id = inclusive - 1u;

    OptIrNodeControl control = opt_ir_control[node];
    control.block_id = block_id;
    opt_ir_control[node] = control;

    if (start == 0u || block_id >= gParams.block_capacity) return;
    uint source = opt_ir_source_hir[node];
    OptIrBlock block;
    block.function_id = source < gParams.hir_capacity
        ? semantic_function_id_by_hir[source] : INVALID;
    block.position_start = position;
    block.terminator = INVALID;
    block.edge_range = opt_ir_pack_block_edges(0u, 0u);
    opt_ir_blocks[block_id] = block;
}
