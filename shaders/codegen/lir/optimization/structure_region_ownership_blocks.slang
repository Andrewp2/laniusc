// Assigns block-entry region ownership from the same interval-stabbing tree.

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
StructuredBuffer<uint> opt_ir_region_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrRegion> opt_ir_regions;
StructuredBuffer<uint> opt_ir_region_ownership_tree;
RWStructuredBuffer<uint> opt_ir_block_region;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

uint region_for_position(uint position)
{
    uint cursor = gParams.semantic_capacity + position;
    uint encoded = 0u;
    while (cursor != 0u)
    {
        encoded = max(encoded, opt_ir_region_ownership_tree[cursor]);
        cursor >>= 1u;
    }
    return encoded == 0u ? INVALID : encoded - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= block_total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    uint region_id = block.position_start < gParams.semantic_capacity
        ? region_for_position(block.position_start) : INVALID;
    bool valid = block.position_start < gParams.semantic_capacity;
    if (region_id != INVALID)
    {
        uint region_total = min(opt_ir_region_total[0u], gParams.block_capacity);
        valid = valid && region_id < region_total;
        if (valid)
        {
            OptIrRegion region = opt_ir_regions[region_id];
            valid = region.function_id == block.function_id &&
                region.position_start <= block.position_start &&
                block.position_start < region.position_end;
        }
    }
    if (!valid)
    {
        report_structure_failure(block_id);
        return;
    }
    opt_ir_block_region[block_id] = region_id;
}
